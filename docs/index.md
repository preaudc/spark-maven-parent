# How to not package Hadoop / Spark transitive dependencies in Spark applications components

A Spark applications component is frequently oversized because it contains jars (i.e. Hadoop, Scala, or even Spark jars) which are already included by Hadoop / Spark.

Besides, this jars are useless because by default Spark always gives precedence to jars provided by Hadoop / Spark over the ones packaged with the Spark applications component.

On the other hand, it is sometimes necessary to include a more recent version of a jar already included by Hadoop / Spark, but it would be dangerous to always give precedence to jars packaged with the Spark applications component, because they could include the wrong Hadoop, Spark or Scala version.

Common solutions to this issue consist in either to:
- package all your dependencies (Spark + Spark applications) in an über jar
- shade the dependencies in common by e.g. using the maven-shade-plugin

I will present below a third solution, which allows to automatically exclude from the Spark applications component the dependencies in common with Hadoop / Spark (and still allows to override safely some of them when necessary).

## Step-by-step guide

### Create a parent POM with all the Hadoop / Spark dependencies
Listing and writing down the more than 200 Hadoop / Spark dependencies being a bit tedious, I have created a quick & dirty perl help script for that purpose.
- Usage:
  - Edit the script and adapt the lines below (at the top of the files) to your environment
The command to list all the Hadoop / Spark jars (`REMOTE_CMD`) is especially important:
```perl
## BEGIN - CUSTOM CONF
# needed to get the list of spark / hadoop jars dependencies
my $REMOTE_CMD = "ls -1 {/opt/hadoop/share/hadoop/*/lib,/opt/spark/jars}/*.jar";

# pom properties
my $HADOOP_VERSION = "2.8.3";
my $JDK_VERSION = "1.8";
my $SCALA_BINARY_VERSION = "2.11";
my $SCALA_VERSION = "2.11.12";
my $SHORT_SCALA_BINARY_VERSION = "11";
my $SPARK_VERSION = "2.4.0";
## END - CUSTOM CONF
```
  - Launch the script with the command below to generate the parent POM sparkMavenParent template:
```shell
# the command below creates a file pom.xml.template
./src/main/scripts/createSparkMavenParentPom.pl -hostname HOSTNAME
```
N.B.: you need to be able to SSH to HOSTNAME
  - Complete / update the parent POM sparkMavenParent template and rename it to `pom.xml`

### Set the POM parent to sparkMavenParent

```xml
    <parent>
       <groupId>my.group.id</groupId>
       <artifactId>sparkMavenParent</artifactId>
       <version>1.0.0</version>
    </parent>
```

### Do not declare version and scope of Spark dependencies
Since they are already defined in sparkMavenParent, they will be ignored anyway, e.g.:

```xml
<dependency>
   <groupId>org.apache.spark</groupId>
   <artifactId>spark-hive_${scala.binary.version}</artifactId>
</dependency>
<dependency>
   <groupId>org.apache.spark</groupId>
   <artifactId>spark-mllib_${scala.binary.version}</artifactId>
</dependency>
```

### Add hadoop-client dependency if necessary (it is NOT provided by Hadoop / Spark)

```xml
<dependency>
   <groupId>org.apache.hadoop</groupId>
   <artifactId>hadoop-client</artifactId>
   <version>${hadoop.version}</version>
</dependency>
```

### Do not declare version of spark-testing-base dependency
It is already defined in sparkMavenParent:

```xml
<dependency>
   <groupId>com.holdenkarau</groupId>
   <artifactId>spark-testing-base_${scala.binary.version}</artifactId>
   <scope>test</scope>
</dependency>
```

### Do not overwrite the following properties
They are already defined in sparkMavenParent:

```xml
<properties>
   <hadoop.version>2.8.3</hadoop.version>
   <jdk.version>1.8</jdk.version>
   <scala.binary.version>2.11</scala.binary.version>
   <scala.version>2.11.12</scala.version>
   <short.scala.binary.version>11</short.scala.binary.version>
   <spark.version>2.4.0</spark.version>
</properties>
```

### (Optional) Declare in a `<dependencyManagement>` section the Hadoop / Spark dependencies that DO need to be overwritten

```xml
<dependencyManagement>
   <dependencies>
      <dependency>
         <groupId>com.google.guava</groupId>
         <artifactId>guava</artifactId>
         <version>28.2-jre</version>
         <scope>compile</scope>
      </dependency>
   </dependencies>
</dependencyManagement>
```

### (Optional) Give precedence to jars packaged with the component over Hadoop / Spark jars when loading classes
Set the Spark configuration properties `spark.driver.userClassPathFirst` and `spark.executor.userClassPathFirst` to true when launching your applications (with e.g. spark-submit):
```shell
/opt/spark/bin/spark-submit (...) --conf spark.driver.userClassPathFirst=true --conf spark.executor.userClassPathFirst=true (...)
```

## Hadoop / Spark dependency override

If  you override the Spark / Hadoop dependencies, this means that your Spark application may be compiled and run with a different version of the library.

Let's look at an example with the guava library, which version 11.0.2 is included by Hadoop:
- no guava dependency in your Spark applications component pom.xml:
  - compilation is done with guava-11.0.2
  - guava-11.0.2 jar is NOT packaged with the Spark applications component RPM
  - run is executed with guava-11.0.2
- guava-28.2-jre is added in a  `<dependencies>` section in your Spark applications component pom.xml:
  - compilation is done with guava-28.2-jre
  - guava-28.2-jre jar is NOT packaged with the Spark applications component RPM
  - run is executed with guava-11.0.2
- guava-28.2-jre is added in a `<dependencyManagement>` section in your Spark applications component pom.xml:
  - compilation is done with guava-28.2-jre
  - guava-28.2-jre jar is packaged with the Spark applications component RPM
  - userClassPathFirst value in your spark-submit command:
    - false or not defined: run is executed with guava-11.0.2
    - true: run is executed with guava-28.2-jre
