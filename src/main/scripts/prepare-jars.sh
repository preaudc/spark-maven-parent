#!/usr/bin/sh

# hadoop jars
mkdir -p extlib/hadoop
(cd bintar/hadoop/hadoop-*/share/hadoop && tar -cv {common,hdfs,mapreduce,yarn}/{,lib/}*.jar) | tar -C extlib/hadoop -xf -

# spark jars
mkdir -p extlib/spark
(cd bintar/spark/spark-2.4.5-bin-without-hadoop-scala-2.12 && tar -cv jars) | tar -C extlib/spark -xf -

# create jars file
find extlib -type f ! -name "*-tests.jar" > hadoop_spark_jars.list
