#!/usr/bin/sh

rm -rf extlib

# hadoop jars
if [[ -d $(ls -d bintar/hadoop/hadoop-*/share/hadoop/ 2>/dev/null) ]]; then
  mkdir -p extlib/hadoop
  (cd bintar/hadoop/hadoop-*/share/hadoop/ && tar -c {common,hdfs,mapreduce,yarn}/{,lib/}*.jar) 2>/dev/null | tar -C extlib/hadoop -xf -
fi

# spark jars
if [[ -d $(ls -d bintar/spark/spark-*/) ]]; then
  mkdir -p extlib/spark
  (cd bintar/spark/spark-*/ && tar -c jars) | tar -C extlib/spark -xf -
fi

# create jars file
find extlib/{spark,hadoop} -type f ! -name "*-tests.jar" 2>/dev/null > hadoop_spark_jars.list
