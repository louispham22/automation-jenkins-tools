const gulp = require('gulp');
const ts = require('gulp-typescript');
const sourcemaps = require('gulp-sourcemaps');
const tsProject = ts.createProject("tsconfig.json");
const tsProjectTest = ts.createProject("tsconfig.json");
const merge = require('merge2');
const del = require('del');
const runSequence = require('run-sequence');
const zip = require('gulp-zip');
const install = require('gulp-install');

const packageJson = require('./package.json');

// clean task
gulp.task('build:clean', () =>  {
    return del([packageJson.main]);
});

gulp.task('build:compile', () => {
    let pipe = tsProject.src()
        .pipe(sourcemaps.init())
        .pipe(tsProject())

    return merge(pipe.dts, pipe.js)
        .pipe(sourcemaps.write('.'))
        .pipe(gulp.dest(packageJson.main));
});

gulp.task('build', (callback) => {
    return runSequence('build:clean', 'build:compile', callback);
});

gulp.task('deploy:copy-build', () => {
    return gulp.src([packageJson.main + '/*', packageJson.main + '/**/*', './bin/*', './bin/**/*'], {base: '.'})
        .pipe(gulp.dest('dist/build'));
})

gulp.task('deploy:install', () => {
    return gulp.src(['./package.json','./package-lock.json'])
        .pipe(gulp.dest('./dist/build'))
        .pipe(install({production: true}));
})

gulp.task('deploy:zip', () => {    
    return gulp.src(['./dist/build/*','./dist/build/**/*'], {base: './dist/build'})
        .pipe(zip(packageJson.name + '-' + packageJson.version + '.zip'))
        .pipe(gulp.dest('./dist'));
});

gulp.task('deploy', (callback) => {
    buildSourceMaps=false;

    return runSequence(['build'], ['deploy:copy-build', 'deploy:install'], ['deploy:zip'], callback)
});

gulp.task('default', (callback) => {
    return runSequence(['build'], callback);
});

