import {existsSync, mkdirSync, readFileSync, writeFile} from 'fs';
import {exec} from 'child_process';

const request = require('request-promise-native');

const configFile = process.env.LAMBDA_CONFIG ? process.env.LAMBDA_CONFIG : '/lambda.json';
const mappingFile = process.env.LAMBDA_JOB_MAPPING ? process.env.LAMBDA_JOB_MAPPING : '/mapping.json';
const libDir = process.env.LIB_DIR ? process.env.LIB_DIR : "/home/node/lib";
const envDir = process.env.ENV_DIR ? process.env.ENV_DIR : "/etc/pinit/env.d";
const projectName = process.argv.length > 2 ? process.argv[2] : 'lambda-node-server';
const outDir = process.argv.length > 3 ? process.argv[3] : `/home/node/${projectName}`;

interface JenkinsApiRespose {
    builds: { artifacts: { fileName: string }[], url:string }[]
}

(async () => {

    if (!existsSync(outDir)) {
        mkdirSync(outDir);
    }
 
    let packageJson:any;
    if (!existsSync(`${outDir}/package.json`)) {
        packageJson = {
            name: projectName,
            private: true,
            devDependencies: {
                "lambda-express": "git+http://gerrit.ps.porters.local/hrbc/tiramisu/lambda-express"
            },
            dependencies: {}
        }
    }
    else {
        packageJson = JSON.parse(readFileSync(outDir + "/package.json").toString());
    }    

    let configJson = JSON.parse(readFileSync(configFile, 'utf8'));
    let mappingJson = JSON.parse(readFileSync(mappingFile, 'utf8'));
    let repore = /^((?:git\+)?http):\/\/gerrit\.ps\.porters\.local\/([^#]*)(?:#(.*))?$/

    let errors: string[] = [];
    let externalDeps: {zip: string, moduleName: string}[] = [];

    await Promise.all(configJson.lambdas.filter((entry:any) => !entry.type || entry.type == "node").map((entry:any) => {
        return (async () => {
            // if the repository is mapped to a job, we need to download zip from build server.
            let m = entry.source.match(repore);
            if (m) {
                if (m[1] != 'git+http') {
                    errors.push(`${m[0]}: only git+http source supported at this time.`);
                    return;
                }
        
                let job = mappingJson[m[2]];
                if (job) {
                    let refname = m[3] ? m[3] : "master";

                    try {

                        let resolved: { url:string, ref:string, versionData:string, packageName:string, packageVersion:string } = await (async () => {
                            let refPromise = new Promise<string> ((accept, reject) => {
                                exec(`git ls-remote http://gerrit.ps.porters.local/${m[2]} ${refname} | cut -f1 | head -1`, (error, stdout, stderr) => {
                                    error ? reject(stderr) : accept(stdout);
                                });
                            });                            
                            
                            let apicall: JenkinsApiRespose = JSON.parse(await request(`http://jenkins-hrbc.ps.porters.local/job/${job}/api/json?depth=3`));
        
                            let urls = apicall.builds.filter(b => b.artifacts.filter(a => a.fileName == "version.env").length > 0).map(b => b.url);
        
                            let ref = (await refPromise).trim();
                            
                            for (let url of urls) {
                                let versionData:string = await request(url + "artifact/version.env");
                                let urlrefmatch = versionData.match("BUILD_GIT_COMMIT=(.*)");
                                let pn = versionData.match("PACKAGE_NAME=(.*)");
                                let pv = versionData.match("PACKAGE_VERSION=(.*)");
                                if (urlrefmatch && urlrefmatch[1] == ref && pn && pn[1] && pv && pv[1]) {
                                    return { url, ref, versionData, packageName: pn[1], packageVersion: pv[1] };
                                }
                            }
                            throw "no url for for ref " + ref;
                        })();

                        console.log("resolved " + entry.moduleName + " to ", resolved);

                        // download lib

                        let zip: string = await new Promise<string>((accept, reject) => {
                            let zipFile: string = `${libDir}/${resolved.packageName}-${resolved.packageVersion}-${resolved.ref}.zip`;
                            let url = `${resolved.url}artifact/${resolved.packageName}-${resolved.packageVersion}.zip`;
                            console.log(`downloading: ${url}`);
                            exec(`curl -o ${zipFile} -sL ${url}`, (err, stdout, stderr) => err ? reject(stderr) : accept(zipFile));
                        });
                        await new Promise((accept, reject) => {
                            writeFile(`${envDir}/00_${resolved.ref}_version.env`, resolved.versionData, (err) => err ? reject(err) : accept())
                        });
                        externalDeps.push({zip, moduleName: entry.moduleName});
                    }
                    catch (e) {
                        errors.push(e);
                    }
                    return;
                }
                else {
                    console.log(`no mapping for ${m[2]} provided`)
                }
            }
            packageJson.dependencies[entry.moduleName] = entry.source;
        })();
    }));

    if (errors.length) {
        console.log("There were errors resolving the dependancies: ", errors);
        process.exit(1);
    }

    try {
        // write package.json
        await new Promise((accept, reject) => {
            writeFile(`${outDir}/package.json`, JSON.stringify(packageJson), (err) => err ? reject(err) : accept())
        });

        // trigger npm
        await new Promise((accept, reject) => {
            console.log("running npm i")
            exec("npm i", {cwd: outDir}, (err, stdout, stderr) => err ? reject(stderr) : accept(stdout));
        });

        // link external deps
        await Promise.all(externalDeps.map(dep => {
            let dirname = dep.zip.slice(0, -4);
            return new Promise((accept, reject) => {
                let cmds = [
                    `mkdir ${dirname}`,
                    `pushd ${dirname}`,
                    `unzip -qq ${dep.zip}`,
                    `rm -f ${dep.zip}`,
                    "popd",
                    `ln -s ${dirname} ${outDir}/node_modules/${dep.moduleName}`
                ].join(" && ");
                console.log(`running cmd: ${cmds}`)
                exec(cmds, {cwd: libDir}, (err, stdout, stderr) => err ? reject({cmds, err, stderr}) : accept(stdout));
            });
        }));

        // output lambda config file to env folder
        await new Promise((accept, reject) => {
            let content = [
                `LAMBDA_CONFIG=${configFile}`, 
                `LAMBDA_HOME=${outDir}`,
                `LAMBDA_JAVA=( ${ configJson.lambdas
                    .filter((entry:any) => entry.type == "java")
                    .map((entry:any) => entry.name)
                    .join(" ")} )`
            ].join("\n");
            writeFile(`${envDir}/10_lambda-server.env`, content, (err) => err ? reject(err) : accept())
        });
    }
    catch(e) {
        console.log("Unexpected error", e);
        process.exit(1);
    }
})();