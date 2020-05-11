# How to not package Hadoop / Spark transitive dependencies in SparkApplications components

A Spark applications component is frequently oversized because it contains jars (i.e. Hadoop, Scala, or even Spark jars) which are already included by Hadoop / Spark.

Besides, this jars are useless because by default Spark always gives precedence to jars provided by Hadoop / Spark over the ones packaged with the Spark applications component.

On the other hand, it is sometimes necessary to include a more recent version of a jar already included by Hadoop / Spark, but it would be dangerous to always give precedence to jars packaged with the Spark applications component, because they could include the wrong Hadoop, Spark or Scala version.

Common solutions to this issue are either:
- package all your dependencies (Spark + Spark applications) in an über jar
- shade the dependencies in common by e.g. using the maven-shade-plugin

I will present below a third solution, which allows to automatically exclude from the Spark applications component the dependencies in common with Hadoop / Spark (and still allows to override safely some of them when necessary).

## Step-by-step guide

- Set the POM parent to sparkMavenParent:
```xml
<parent>
   <groupId>your.package.groupid</groupId>
   <artifactId>sparkMavenParent</artifactId>
   <version>1.0.0</version>
</parent>
```

- Do not declare version and scope of Spark dependencies (since they are already defined in sparkMavenParent, they will be ignored anyway), e.g.:
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

- Add hadoop-client dependency if necessary (it is NOT provided by Hadoop / Spark):
```xml
<dependency>
   <groupId>org.apache.hadoop</groupId>
   <artifactId>hadoop-client</artifactId>
   <version>${hadoop.version}</version>
</dependency>
```

- Do not declare version of spark-testing-base dependency (it is already defined in sparkMavenParent):
```xml
<dependency>
   <groupId>com.holdenkarau</groupId>
   <artifactId>spark-testing-base_${scala.binary.version}</artifactId>
   <scope>test</scope>
</dependency>
```

- Do not overwrite the following properties (they are already defined in sparkMavenParent):
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

- (Optional) Declare in a <dependencyManagement> block the Hadoop / Spark dependencies that DO need to be overwritten:
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

- (Optional) Set the Spark configuration properties `spark.driver.userClassPathFirst` and `spark.executor.userClassPathFirst` to true when launching your applications (with e.g. spark-submit) in order to give precedence to jars packaged with the component over Hadoop / Spark jars when loading classes:
```shell
/opt/spark/bin/spark-submit (...) --conf spark.driver.userClassPathFirst=true --conf spark.executor.userClassPathFirst=true (...)
```

## Hadoop / Spark dependency override

If  you override the Spark / Hadoop dependencies, this means that your Spark application may be compiled and run with a different version of the library.

Let's look at an example with the guava library, which version 11.0.2 is included by Hadoop:

- no guava dependency in your SparkApplications component pom.xml:
  - compilation is done with guava-11.0.2
  - guava-11.0.2 jar is NOT packaged with the SparkApplications component RPM
  - run is executed with guava-11.0.2
- guava-28.2-jre is added in a <dependencies> block in your SparkApplications component pom.xml:
  - compilation is done with guava-28.2-jre
  - guava-28.2-jre jar is NOT packaged with the SparkApplications component RPM
  - run is executed with guava-11.0.2
- guava-28.2-jre is added in a <dependencyManagement> block in your SparkApplications component pom.xml:
  - compilation is done with guava-28.2-jre
  - guava-28.2-jre jar is packaged with the SparkApplications component RPM
  - userClassPathFirst value in your sparkAppRunner job properties:
    - false or not defined: run is executed with guava-11.0.2
    - true: run is executed with guava-28.2-jre
