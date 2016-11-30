use information_schema;

-- mysql version
select @@version as mysql_version \G

-- spazio e dati occupati dalle tabelle
select "# db size";
select table_schema, replace(table_type,' ','_'), count(table_name) as tot_tables, engine, sum(table_rows) >>10  table_rows_ki, table_collation, sum(data_length) >> 20 data_mbi, sum(index_length) >> 20 index_mbi,  avg_row_length from information_schema.tables  where table_schema not in ('mysql', 'information_schema', 'performance_schema') group by table_schema, engine, table_type;

-- trigger e routines
select "# triggers";
select count(trigger_name) as t, trigger_schema as s from triggers group by trigger_schema;
select "# triggers";
select count(routine_name) as t, routine_schema as s from routines group by routine_schema;

-- users e definers
select "# users & definers";
select count(definer) as definer_no from  information_schema.views where table_schema not in ('mysql','performance_schema','information_schema') \G
select count(user) as user_no from mysql.user \G

-- partizioni
select "# partitions";
SELECT TABLE_NAME, PARTITION_NAME, PARTITION_EXPRESSION, PARTITION_DESCRIPTION,
    TABLE_ROWS,
    ROUND(DATA_LENGTH / (1024 * 1024), 2) AS DATA_SIZE_MB,
    ROUND(INDEX_LENGTH / (1024 * 1024), 2) AS INDEX_SIZE_MB,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / (1024 * 1024), 2) AS TOTAL_SIZE_MB
FROM information_schema.PARTITIONS
WHERE TABLE_SCHEMA=DATABASE()
AND PARTITION_NAME IS NOT NULL
ORDER BY TABLE_NAME, PARTITION_ORDINAL_POSITION;

-- tabelle senza chiavi
select "# table without keys";
SELECT t.TABLE_SCHEMA,t.TABLE_NAME,ENGINE
FROM information_schema.TABLES t
INNER JOIN information_schema.COLUMNS c
ON t.TABLE_SCHEMA=c.TABLE_SCHEMA
AND t.TABLE_NAME=c.TABLE_NAME
AND t.TABLE_SCHEMA NOT IN ('performance_schema','information_schema','mysql')
GROUP BY t.TABLE_SCHEMA,t.TABLE_NAME
HAVING sum(if(column_key in ('PRI','UNI'), 1,0))=0;


-- buffer e max values
select "# table without keys";
select * from  global_status where  variable_name in ('max_used_connections','threads_connected','uptime_since_flush_status','opened_tables','opened_files','INNODB_BUFFER_POOL_PAGES_FREE','KEY_BLOCKS_UNUSED','BYTES_RECEIVED','BYTES_SENT','CONNECTIONS','QUESTIONS') order by variable_name;

-- temporary tables
select * from  global_status where  variable_name like '%tmp%';
select @@tmp_table_size >> 20 max_tmp_table_size_mb, 
	@@max_heap_table_size >>20 max_heap_table_size_mb \G


