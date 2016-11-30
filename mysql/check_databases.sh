#!/usr/bin/bash
# usage: check_databases.sh -uUSER -pPASS -hHOST ..

MYSQL="mysql  $@  -b --skip-column-names "
MYSQL_W="mysql  $@  -b  "

header(){
	echo
	echo "#"
	echo "# $@"
	echo "#"
}

check_null_values_in_notnull_columns(){
	header " check_null_values_in_notnull_columns"
columns=$($MYSQL information_schema -e "select concat_ws('.',concat('\`', table_schema, '\`') , concat('\`', table_name, '\`') , concat('\`', column_name,'\`') ) 
	from information_schema.columns 
	where 
       		table_schema not in ('mysql', 'sys', 'performance_schema', 'information_schema', 'test') 
        	and is_nullable='NO'
	;")
OLDIFS="$IFS"
IFS=$'\n'
all=($columns)
IFS="$OLDIFS"
for k in "${all[@]}"; do
	table="${k%.*}"
	query="SELECT count(*) from $table where $k is NULL;";
	echo -e "Checking for null fields in $k: count (limited to 10) " $($MYSQL -e "$query")
done
}

check_row_format(){
	header "# check_row_format"
	echo "InnoDB tables with unsupported row format: FIXED";
	$MYSQL -e "select concat_ws('.', table_schema, table_name) from  information_schema.tables where engine = 'innodb' and row_format = 'FIXED';"
}


check_zero_dates(){
	header "# check_zero_dates"
	echo "Date columns with zero defaults. See http://dev.mysql.com/doc/refman/5.7/en/datetime.html
		Supported dates are '1000-01-01' to '9999-12-31' '1000-01-01 00:00:00' to '9999-12-31 23:59:59'
		TIMESTAMP has a range of '1970-01-01 00:00:01' UTC to '2038-01-19 03:14:07' UTC. 

	"
	$MYSQL -e  "select table_schema,table_name,column_name,column_type,column_default  
			from information_schema.columns 
			where 
				table_schema not in ('mysql', 'sys', 'performance_schema', 'information_schema') 
				and data_type in ('date','datetime','timestamp') 
				and ( column_default like '0%' or column_default is NULL);
		"

}

run_assessment(){
	header "# run assessment"
	echo "Run a set of assement queries"
	$MYSQL_W < mysql_assessment.sql
}

# Run checks
check_row_format
check_null_values_in_notnull_columns
check_zero_dates
run_assessment
