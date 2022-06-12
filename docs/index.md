# Exclude Spark dependencies from your Spark applications component

A Spark application component is frequently oversized because it contains jars (i.e. Spark, Scala, or even Hadoop jars) which are already included by Spark / Hadoop.

Besides, these jars are useless because by default Spark always gives precedence to jars provided by Spark / Hadoop over the ones packaged with the Spark applications component.

On the other hand, it is sometimes necessary to include a more recent version of a jar already included by Spark / Hadoop, but it would be dangerous to always give precedence to jars packaged with the Spark applications component, because they could include jars with the wrong Hadoop, Spark or Scala version.

Common solutions to this issue consist in either to:
- Shade the dependencies in common by e.g. using the maven-shade-plugin.
- Package all your dependencies (Spark + Spark applications) in an über jar.

I will present below a third solution, which allows to automatically exclude from the Spark applications component the dependencies in common with Spark / Hadoop.
Additionally, it provides a safe way to override some of these dependencies when necessary.

## Step-by-step guide

This solution consists in:
1. Creating a parent POM **spark-maven-parent** which will include all the Spark / Hadoop dependencies with a **provided** scope (see e.g. this example: [pom.xml.template](https://github.com/preaudc/spark-maven-parent/blob/master/pom.xml.template))
1. Set the parent POM of your Spark applications component to **spark-maven-parent** so that all Spark / Hadoop dependencies are automatically excluded at the packaging step.

### 1. Create a parent POM with all the Spark / Hadoop dependencies
Listing and writing down the more than 200 Spark / Hadoop dependencies being a bit tedious, I have created a quick & dirty python helper script ([create-spark-parent-pom.py](https://github.com/preaudc/spark-maven-parent/blob/master/create-spark-parent-pom.py)) for that purpose.

#### 1.1 Edit the configuration file ([conf/create-spark-parent-pom.yaml](https://github.com/preaudc/spark-maven-parent/blob/master/conf/create-spark-parent-pom.yaml)) and adapt the lines below (at the top of the file) to your environment
```yaml
project_pom:
  'group_id': 'my.group.id'
  'artifact_id': 'spark-maven-parent'
  'version': '1.0.0-SNAPSHOT'
  'description': 'Parent POM for Spark applications components'
properties_version:
  'jdk_version': '1.8'
```

#### 1.2 Launch the script with the command below to generate the parent POM spark-maven-parent template:

```shell
# the command below creates a file pom.xml.template
./create-spark-parent-pom.py --provided --output-file pom.xml.template JARS_FILE
```

**N.B.**:
- _**JARS_FILE**_ is a file containing all the path of the the Spark / Hadoop jars dependencies, you can create it for example with 
the steps below:
  - create a `extlib` directory to store (Hadoop and) Spark jars
  - copy Hadoop jars in extlib/hadoop (if you use a pre-built Apache Spark package with user-provided Apache Hadoop)
  - copy Spark jars in extlib/spark
  - create the JARS_FILE with the following command: `find extlib/{spark,hadoop} -type f ! -name "*-tests.jar" 2>/dev/null > hadoop_spark_jars.list`
- The `create-spark-parent-pom.py` script will scan the `$HOME/.m2` repository on your local machine to try to get the group and artifact ids from the Spark / Hadoop jar name and version (I said it was quick & dirty ;-) ). If unsuccessful, it will try to get the group id from a web service on search.maven.org using the SHA1SUM of the jar as parameter.

#### 1.3 Complete / update the parent POM spark-maven-parent template and rename it to `pom.xml`

#### 1.4 Compile and deploy it

### 2. Update your Spark applications component POM

#### 2.1 Set the POM parent to spark-maven-parent

```xml
    <parent>
       <groupId>my.group.id</groupId>
       <artifactId>spark-maven-parent</artifactId>
       <version>1.0.0</version>
    </parent>
```

#### 2.2 Add hadoop-client dependency if necessary (it is NOT provided by Spark / Hadoop)

```xml
<dependency>
   <groupId>org.apache.hadoop</groupId>
   <artifactId>hadoop-client</artifactId>
   <version>${hadoop.version}</version>
</dependency>
```

#### 2.3 Do not declare version and scope of Spark dependencies
Since they are already defined in **spark-maven-parent**, they will be ignored anyway, e.g.:

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

#### 2.4 Do not overwrite the following properties
They are already defined in **spark-maven-parent**:

```xml
<properties>
   <hadoop.version>3.3.1</hadoop.version>
   <jdk.version>1.8</jdk.version>
   <scala.binary.version>2.13</scala.binary.version>
   <scala.version>2.13.5</scala.version>
   <spark.version>3.2.1</spark.version>
</properties>
```

#### 2.5 (Optional) Declare in a `<dependencyManagement>` section the Spark / Hadoop dependencies that DO need to be overwritten

If the dependency version is greater than the Spark / Hadoop dependency one:

Declare this dependency in a `<dependencyManagement>` section:
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

If the dependency version is lower than the Spark / Hadoop dependency one:

Declare this dependency in a `<dependencyManagement>` section:
```xml
<dependencyManagement>
   <dependencies>
      <dependency>
         <groupId>org.json4s</groupId>
         <artifactId>json4s-core_${scala.binary.version}</artifactId>
         <version>3.2.11</version>
         <scope>compile</scope>
      </dependency>
   </dependencies>
</dependencyManagement>
```

Declare also this dependency (without version and scope) in a `<dependencies>` section:
```xml
<dependencies>
   (...)
   <dependency>
      <groupId>org.json4s</groupId>
      <artifactId>json4s-core_${scala.binary.version}</artifactId>
   </dependency>
   (...)
<dependencies>
```

#### 2.6 (Optional) Give precedence to jars packaged with the component over Spark / Hadoop jars when loading classes
Set the Spark configuration properties `spark.driver.userClassPathFirst` and `spark.executor.userClassPathFirst` to true when launching your applications (with e.g. `spark-submit`):
```shell
/opt/spark/bin/spark-submit (...) --conf spark.driver.userClassPathFirst=true --conf spark.executor.userClassPathFirst=true (...)
```

## Notes on Spark / Hadoop dependency override
If you override the Spark / Hadoop dependencies, this means that your Spark application may be compiled and run with a different version of the library.

Let's look at an example with the guava library, which version 11.0.2 is included by Hadoop-2.8.3:
- no guava dependency in your Spark applications component `pom.xml`:
  - compilation is done with _**guava-11.0.2**_
  - _**guava-11.0.2**_ jar is NOT packaged with the Spark applications component RPM
  - run is executed with _**guava-11.0.2**_
- _**guava-28.2-jre**_ is added in a `<dependencies>` section in your Spark applications component `pom.xml`:
  - compilation is done with _**guava-28.2-jre**_
  - _**guava-28.2-jre**_ jar is NOT packaged with the Spark applications component RPM
  - run is executed with _**guava-11.0.2**_
- _**guava-28.2-jre**_ is added in a `<dependencyManagement>` section in your Spark applications component `pom.xml`:
  - compilation is done with _**guava-28.2-jre**_
  - _**guava-28.2-jre**_ jar is packaged with the Spark applications component RPM
  - userClassPathFirst value in your `spark-submit` command:
    - false or not defined: run is executed with _**guava-11.0.2**_
    - true: run is executed with _**guava-28.2-jre**_

Another example with the json4s libraries, which version 3.5.3 is included by Spark-2.4.5:
- no json4s dependency in your Spark applications component `pom.xml`:
  - compilation is done with _**json4s-3.5.3**_
  - _**json4s-3.5.3**_ jar is NOT packaged with the Spark applications component RPM
  - run is executed with _**json4s-3.5.3**_
- _**json4s-3.2.11**_ is added in a `<dependencies>` section in your Spark applications component `pom.xml`:
  - compilation is done with _**json4s-3.2.11**_
  - _**json4s-3.2.11**_ jar is NOT packaged with the Spark applications component RPM
  - run is executed with _**json4s-3.5.3**_
- _**json4s-3.2.11**_ is added in a `<dependencyManagement>` section in your Spark applications component `pom.xml`:
  - compilation is done with _**json4s-3.2.11**_
  - _**json4s-3.2.11**_ jar is NOT packaged with the Spark applications component RPM
  - userClassPathFirst value in your `spark-submit` command:
    - false or not defined: run is executed with _**json4s-3.5.3**_
    - true: run is executed with _**json4s-3.2.11**_ (and fails because _**json4s-3.2.11**_ jar is not packaged with the Spark applications component RPM)
- _**json4s-3.2.11**_ is added both in a `<dependencyManagement>` section and in a `<dependencies>` section in your Spark applications component pom.xml:
  - compilation is done with _**json4s-3.2.11**_
  - _**json4s-3.2.11**_ jar is packaged with the Spark applications component RPM
  - userClassPathFirst value in your `spark-submit` command:
    - false or not defined: run is executed with _**json4s-3.5.3**_
    - true: run is executed with _**json4s-3.2.11**_
