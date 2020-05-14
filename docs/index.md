# How to not package Hadoop / Spark transitive dependencies in Spark applications components

A Spark applications component is frequently oversized because it contains jars (i.e. Hadoop, Scala, or even Spark) which are already included by Hadoop / Spark.

Besides, these jars are useless because by default Spark always gives precedence to jars provided by Hadoop / Spark over the ones packaged with the Spark applications component.

On the other hand, it is sometimes necessary to include a more recent version of a jar already included by Hadoop / Spark, but it would be dangerous to always give precedence to jars packaged with the Spark applications component, because they could include jars with the wrong Hadoop, Spark or Scala version.

Common solutions to this issue consist in either to:
- Shade the dependencies in common by e.g. using the maven-shade-plugin.
- Package all your dependencies (Spark + Spark applications) in an über jar.

I will present below a third solution, which allows to automatically exclude from the Spark applications component the dependencies in common with Hadoop / Spark (and still allows to override safely some of them when necessary).

## Step-by-step guide

This solution consists in:
1. Creating a parent POM **sparkMavenParent** which will include all the Hadoop / Spark dependencies with a **provided** scope (see e.g. this example: [pom.xml.template](https://github.com/preaudc/spark-maven-parent/blob/master/pom.xml.template))
1. Set the parent POM of your Spark applications component to **sparkMavenParent** so that all Hadoop / Spark dependencies are automatically excluded at the packaging step.

### 1. Create a parent POM with all the Hadoop / Spark dependencies
Listing and writing down the more than 200 Hadoop / Spark dependencies being a bit tedious, I have created a quick & dirty perl helper script ([createSparkMavenParentPom.pl](https://github.com/preaudc/spark-maven-parent/blob/master/src/main/scripts/createSparkMavenParentPom.pl)) for that purpose.

#### 1.1 Edit the script and adapt the lines below (at the top of the file) to your environment

```perl
## BEGIN - CUSTOM CONF
# pom properties
my $HADOOP_VERSION = "2.8.3";
my $JDK_VERSION = "1.8";
my $SCALA_BINARY_VERSION = "2.12";
my $SCALA_VERSION = "2.12.10";
my $SHORT_SCALA_BINARY_VERSION = "12";
my $SPARK_VERSION = "2.4.5";
## END - CUSTOM CONF
```

#### 1.2 Launch the script with the command below to generate the parent POM sparkMavenParent template:

```shell
# the command below creates a file pom.xml.template
./createSparkMavenParentPom.pl -file JARS_FILE
```

**N.B.**:
- This script works best if the Hadoop / Spark jars are copied locally (Hadoop jars in a `hadoop` directory, Spark jars in a `spark` directory). This can be done with the commands below:
  - create directory to store Hadoop and Spark jars
    - `mkdir extlib`
  - copy Hadoop jars in extlib/hadoop
    - `ssh <HADOOP_SPARK_HOSTNAME> "cd /opt/hadoop/share && tar -cv hadoop/*/lib/*.jar" | tar -C extlib -xf -`
  - copy Spark jars in extlib/spark
    - `ssh <HADOOP_SPARK_HOSTNAME> "cd /opt && tar -cv spark/jars/*.jar" | tar -C extlib -xf -`
- _**JARS_FILE**_ is a file containing all the Hadoop / Spark jars dependencies, you can create it for example with the following command: `find extlib -type f > hadoop_spark_jars.list`
- This script will scan the `$HOME/.m2` repository on your local machine to try to get the group and artifact ids from the Hadoop / Spark jar name and version (I said it was quick & dirty ;-) ). If unsuccessful, it will try to get the group id from a web service on search.maven.org using the SHA1SUM of the jar as parameter.

#### 1.3 Complete / update the parent POM sparkMavenParent template and rename it to `pom.xml`

#### 1.4 Compile and deploy it

### 2. Update your Spark applications component POM

#### 2.1 Set the POM parent to sparkMavenParent

```xml
    <parent>
       <groupId>my.group.id</groupId>
       <artifactId>sparkMavenParent</artifactId>
       <version>1.0.0</version>
    </parent>
```

#### 2.2 Do not declare version and scope of Spark dependencies
Since they are already defined in **sparkMavenParent**, they will be ignored anyway, e.g.:

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

#### 2.3 Add hadoop-client dependency if necessary (it is NOT provided by Hadoop / Spark)

```xml
<dependency>
   <groupId>org.apache.hadoop</groupId>
   <artifactId>hadoop-client</artifactId>
   <version>${hadoop.version}</version>
</dependency>
```

#### 2.4 Do not declare version of spark-testing-base dependency
It is already defined in **sparkMavenParent**:

```xml
<dependency>
   <groupId>com.holdenkarau</groupId>
   <artifactId>spark-testing-base_${scala.binary.version}</artifactId>
   <scope>test</scope>
</dependency>
```

#### 2.5 Do not overwrite the following properties
They are already defined in **sparkMavenParent**:

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

#### 2.6 (Optional) Declare in a `<dependencyManagement>` section the Hadoop / Spark dependencies that DO need to be overwritten

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

#### 2.7 (Optional) Give precedence to jars packaged with the component over Hadoop / Spark jars when loading classes
Set the Spark configuration properties `spark.driver.userClassPathFirst` and `spark.executor.userClassPathFirst` to true when launching your applications (with e.g. `spark-submit`):
```shell
/opt/spark/bin/spark-submit (...) --conf spark.driver.userClassPathFirst=true --conf spark.executor.userClassPathFirst=true (...)
```

## Notes on Hadoop / Spark dependency override
If  you override the Spark / Hadoop dependencies, this means that your Spark application may be compiled and run with a different version of the library.

Let's look at an example with the guava library, which version 11.0.2 is included by Hadoop:
- no guava dependency in your Spark applications component `pom.xml`:
  - compilation is done with _**guava-11.0.2**_
  - _**guava-11.0.2**_ jar is NOT packaged with the Spark applications component RPM
  - run is executed with _**guava-11.0.2**_
- _**guava-28.2-jre**_ is added in a  `<dependencies>` section in your Spark applications component `pom.xml`:
  - compilation is done with _**guava-28.2-jre**_
  - _**guava-28.2-jre**_ jar is NOT packaged with the Spark applications component RPM
  - run is executed with _**guava-11.0.2**_
- _**guava-28.2-jre**_ is added in a `<dependencyManagement>` section in your Spark applications component `pom.xml`:
  - compilation is done with _**guava-28.2-jre**_
  - _**guava-28.2-jre**_ jar is packaged with the Spark applications component RPM
  - userClassPathFirst value in your `spark-submit` command:
    - false or not defined: run is executed with _**guava-11.0.2**_
    - true: run is executed with _**guava-28.2-jre**_
