#!/bin/bash
#
# input format for input.txt
#id:company:name:login:password:lang:tz:db:trialendoraccountstart:trialflgoraccountend
#
# if trialflgoraccountend == trial, then db is trial type and trialendoraccountstart is trial end date
# otherwise trialendoraccountstart is accound start date or today. trialflgoraccountend is account
# end date or 5 yrs from now

# truncate post-init.sql
echo -n "" > post-init.sql

DATE=$(date +"%Y/%m/%d %H:%M:%S")
DB_IDS=""
DELIM=" ";
for line in $(cat input.txt); do
	id=$(echo $line | cut -d"," -f1);
	company=$(echo $line | cut -d"," -f2);
	name=$(echo $line | cut -d"," -f3);
	mail=$(echo $line | cut -d"," -f4);
	password=$(echo $line | cut -d"," -f5);
	lang=$(echo $line | cut -d"," -f6);
	tz=$(echo $line | cut -d"," -f7);
	db=$(echo $line | cut -d"," -f8);
	trialendoraccountstart=$(echo $line | cut -d"," -f9);
	trialflgoraccountend=$(echo $line | cut -d"," -f10);

	if [[ "trial" == "$trialflgoraccountend" ]]; then
		[ -n "$trialendoraccountstart" ] && trial="'$trialendoraccountstart'" || trial="'2020-12-31 23:59:59'";
		dbtype=1
		accountstart="NULL"
		accountend="NULL"
	else
		trial="NULL"
		dbtype=2
		[ -n "$trialendoraccountstart" ] && accountstart="'$trialendoraccountstart'" || accountstart="'$(date -Idate) 00:00:00'";
		[ -n "$trialflgoraccountend" ] && accountend="'$trialflgoraccountend'" || accountend="'$(date -Idate -d '+5years') 23:59:59'"
	fi

	[ -n "$db" ] || db=1;
	[ -n "$tz" ] || tz="Asia/Tokyo"
	[ -n "$lang" ] || lang="ja"
	[ -n "$password" ] || password="password"
	[ -n "$mail" ] || mail="test@porters.jp"
	[ -n "$name" ] || name="Test Tester"
	
	echo "SQL: INSERT INTO office.interim_agents (id, do_flg, hash, url, name, password, mail, tel, company_name, post_name, dept_name, agent_count, template_id, regist_date, update_date, language, time_zone, knowing_source, job_count, candidate_count, regist_type, master_template_id) VALUE(${id:-NULL}, 0, '68a435caa16ad480af750324721c83e3fb693b84', NULL, '$name', NULL, '$mail', '09000000001', '${company:-PRC}', NULL, NULL, 10, NULL, '${DATE}', '${DATE}', '${lang}', '${tz}', 1, 1, 1, 1, 1);"
	mysql -uroot -prootpass -e "INSERT INTO office.interim_agents (id, do_flg, hash, url, name, password, mail, tel, company_name, post_name, dept_name, agent_count, template_id, regist_date, update_date, language, time_zone, knowing_source, job_count, candidate_count, regist_type, master_template_id) VALUE(${id:-NULL}, 0, '68a435caa16ad480af750324721c83e3fb693b84', NULL, '$name', NULL, '$mail', '09000000001', '${company:-PRC}', NULL, NULL, 10, NULL, '${DATE}', '${DATE}', '${lang}', '${tz}', 1, 1, 1, 1, 1);"

	[ -n "$id" ] || id=$(mysql -B --skip-column-names -uroot -prootpass -e "SELECT id FROM office.interim_agents WHERE update_date='${DATE}' ORDER BY id DESC LIMIT 1;");
	[ -n "$company" ] || company="PRC$id"

	echo "ID: $id COMPANY: $company"	

	echo "SQL: INSERT INTO office.companies(id, company_login_id, name, register_name, mail, tel, free_trial_end_date, accounting_start_date, accounting_end_date, demo_flg, init_work_id, status_id, db_info_id, regist_date, update_date, language, time_zone, db_type, db_type_con, plan, master_template_id) VALUES ('${id}', '${company}', '${company}', '${name}', '${mail}', '0900000001', ${trial}, ${accountstart}, ${accountend}, 0, 0, ${dbtype}, ${db}, '${DATE}', '${DATE}', '${lang}', '${tz}', 'PRC', 'PRC${id}', 0, 1);"
	mysql -uroot -prootpass -e "INSERT INTO office.companies(id, company_login_id, name, register_name, mail, tel, free_trial_end_date, accounting_start_date, accounting_end_date, demo_flg, init_work_id, status_id, db_info_id, regist_date, update_date, language, time_zone, db_type, db_type_con, plan, master_template_id) VALUES ('${id}', '${company}', '${company}', '${name}', '${mail}', '0900000001', ${trial}, ${accountstart}, ${accountend}, 0, 0, ${dbtype}, ${db}, '${DATE}', '${DATE}', '${lang}', '${tz}', 'PRC', 'PRC${id}', 0, 1);"

	if [[ "$trial" != "NULL" ]]; then
		echo "POSTSQL: UPDATE office.companies SET free_trial_end_date=${trial} WHERE id=${id};"
	else
		echo "POSTSQL: UPDATE office.companies SET accounting_start_date=${accountstart}, accounting_end_date=${accountend} WHERE id=${id};"
	fi
	echo "POSTSQL: UPDATE PRC${id}.agents SET password=MD5(CONCAT('${password}','plmkoijnbhuygvcftrdxsewazq')) WHERE id='1';"
	if [[ "$trial" != "NULL" ]]; then
		echo "UPDATE office.companies SET free_trial_end_date=${trial} WHERE id=${id};" >> post-init.sql
	else
		echo "UPDATE office.companies SET accounting_start_date=${accountstart}, accounting_end_date=${accountend} WHERE id=${id};" >> post-init.sql
	fi
	echo "UPDATE PRC${id}.agents SET password=MD5(CONCAT('${password}','plmkoijnbhuygvcftrdxsewazq')) WHERE id='1';" >> post-init.sql
	
	if test "${DB_IDS#*$db}" == "$DB_IDS"
	then
		DB_IDS=$DB_IDS$DELIM$db
	fi

	echo "DBS: $DB_IDS"
	
done

if $(grep -o "$DELIM" <<< $DB_IDS)
then
	for dbid in ${DB_IDS}; do
		
		fullLengthNum=$dbid
		printf -v fullLengthNum "%02d" $dbid
		echo "SQL: INSERT INTO office.db_info (id, type, display_name, host, port, user_name, password, nametemplate)  VALUES (${dbid}, 1, 'db_${fullLengthNum}', 'db01', 3306, 'root', 'rootpass', 'PRC' ) ON DUPLICATE KEY UPDATE display_name='db_${fullLengthNum}'"
		mysql -uroot -prootpass -e "INSERT INTO office.db_info (id, type, display_name, host, port, user_name, password, nametemplate)  VALUES (${dbid}, 1, 'db_${fullLengthNum}', 'db01', 3306, 'root', 'rootpass', 'PRC' ) ON DUPLICATE KEY UPDATE display_name='db_${fullLengthNum}'"
		
		echo "POSTSQL: UPDATE office.db_info SET host='db${fullLengthNum}' WHERE id=${dbid};"
		echo "UPDATE office.db_info SET host='db${fullLengthNum}' WHERE id=${dbid};" >> post-init.sql
	done
fi
