# Running the Hive scripts on HDInsight

These steps assume a Hadoop HDInsight cluster with SSH access, like the one used in the Pass/Credit tasks. Replace `CLUSTERNAME` and `sshuser` with your own.

## 1. Copy the CSVs and scripts to the cluster
From the project folder on your own computer:
```bash
scp data/raw/person.csv data/raw/vehicle.csv data/raw/accident.csv sshuser@CLUSTERNAME-ssh.azurehdinsight.net:~
scp hive/*.hql sshuser@CLUSTERNAME-ssh.azurehdinsight.net:~
```

## 2. SSH in and put the CSVs into cluster storage
```bash
ssh sshuser@CLUSTERNAME-ssh.azurehdinsight.net

hdfs dfs -mkdir -p /crashdata/person /crashdata/vehicle /crashdata/accident
hdfs dfs -put -f person.csv   /crashdata/person/
hdfs dfs -put -f vehicle.csv  /crashdata/vehicle/
hdfs dfs -put -f accident.csv /crashdata/accident/
hdfs dfs -ls -R /crashdata
```
📸 Screenshot the `hdfs dfs -ls -R` output.

## 3. Run the scripts with Beeline
```bash
BL="beeline -u 'jdbc:hive2://headnodehost:10001/;transportMode=http'"

eval $BL -f 01_create_tables.hql
eval $BL -f 02_build_occupants.hql
eval $BL -f 03_summary_queries.hql
```
If `eval` gives you trouble, just paste the full beeline command each time:
`beeline -u 'jdbc:hive2://headnodehost:10001/;transportMode=http' -f 01_create_tables.hql`

You can also open Beeline interactively (same command without `-f ...`) and paste queries one at a time. That's easier for screenshots, because each query and its result appear together.

## 4. Export the final tables to CSV for R
```bash
beeline -u 'jdbc:hive2://headnodehost:10001/;transportMode=http' \
  --outputformat=csv2 --showHeader=true --silent=true \
  -e "SELECT * FROM crash.occupants_final" > occupants_final.csv

beeline -u 'jdbc:hive2://headnodehost:10001/;transportMode=http' \
  --outputformat=csv2 --showHeader=true --silent=true \
  -e "SELECT * FROM crash.occupants_sensitivity" > occupants_sensitivity.csv

wc -l occupants_final.csv occupants_sensitivity.csv
head -3 occupants_final.csv
```
Then, back on your own computer:
```bash
scp sshuser@CLUSTERNAME-ssh.azurehdinsight.net:~/occupants_*.csv data/processed/
```
Check that the first line of each CSV is the header and that there are no stray log lines at the top. If there are, delete them in a text editor.

## 5. Delete the cluster when you're done
HDInsight charges by the hour while it's running, even when idle. The CSVs you exported are safe on your own machine.

## Expected results (to check your output)
These came from running the same logic outside Hive. Your Hive counts should match exactly. If they don't, check the table LOCATION paths and that the header row was skipped.

| Step | Table | Expected rows |
|---|---|---:|
| Load | person_raw | 425,352 |
| Load | vehicle_raw | 331,992 |
| Load | accident_raw | 182,039 |
| A | vehicle_other | 331,992 |
| 1 | occ_s1_joined | 408,264 |
| 2 | occ_s2_front | 363,984 |
| 3 | occ_s3_light | 288,823 |
| 4 | occ_s4_sex | 282,399 |
| 5 | occupants_final (belt = 1) | 194,061 |
| Sensitivity | occupants_sensitivity (belt = 1 or 9) | 273,850 |

Expected Q1 result (KSI by sex, final table):
| Sex | n | KSI | KSI % |
|---|---:|---:|---:|
| F | 95,942 | 17,640 | 18.39 |
| M | 98,119 | 14,466 | 14.74 |
