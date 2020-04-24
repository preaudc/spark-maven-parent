#!/usr/bin/perl

use strict;
use warnings;

# needed to get the list of spark / hadoop jars dependencies
my $REMOTE_CMD = "ls -1 /opt/kookel/{kelkooHadoop*,kelkooSparkLib}/current/javalib/*.jar";
my $SPARK_HOST="dc1-kdp-prod-spark-01.prod.dc1.kelkoo.net";

# pom parents version
my $KELKOO_SPARK_MAVEN_PARENT_VERSION = "1.2.1-SNAPSHOT";
my $KELKOO_MAVEN_PARENT_VERSION = "2.9.1";

# pom properties
my $HADOOP_VERSION = "2.8.3";
my $JDK_VERSION = "1.8";
my $SCALA_BINARY_VERSION = "2.11";
my $SCALA_VERSION = "2.11.12";
my $SHORT_SCALA_BINARY_VERSION = "11";
my $SPARK_VERSION = "2.4.0";

my $pom_header = qq(<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">

   <!-- PROJECT DESCRIPTION SECTION -->
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.kelkoogroup.dataplatform</groupId>
   <artifactId>kelkooSparkMavenParent</artifactId>
   <version>$KELKOO_SPARK_MAVEN_PARENT_VERSION</version>
   <packaging>pom</packaging>
   <name>kelkooSparkMavenParent</name>
   <description>Common component for dataplatform applications</description>

   <!-- PARENT SECTION -->
   <parent>
      <groupId>com.kelkoo</groupId>
      <artifactId>kelkooMavenParent</artifactId>
      <version>$KELKOO_MAVEN_PARENT_VERSION</version>
   </parent>

   <!-- Source control management SECTION -->
   <scm>
      <connection>scm:git|git\@gitlab.corp.kelkoo.net:data-platform/kelkoosparkmavenparent.git</connection>
      <url>http://gitlab.corp.kelkoo.net/data-platform/kelkoosparkmavenparent</url>
      <tag>HEAD</tag>
   </scm>

   <!-- DEPENDENCIES SECTION -->
   <dependencyManagement>
      <dependencies>

         <!-- External dependencies -->);

my $pom_footer = qq(         <!-- Test dependencies -->
         <dependency>
            <groupId>com.holdenkarau</groupId>
            <artifactId>spark-testing-base_\${scala.binary.version}</artifactId>
            <version>\${spark.version}_0.\${short.scala.binary.version}.0</version>
            <scope>test</scope>
         </dependency>
      </dependencies>
   </dependencyManagement>

   <!-- PROPERTIES SECTION -->
   <properties>
      <hadoop.version>$HADOOP_VERSION</hadoop.version>
      <jdk.version>$JDK_VERSION</jdk.version>
      <scala.binary.version>$SCALA_BINARY_VERSION</scala.binary.version>
      <scala.version>$SCALA_VERSION</scala.version>
      <short.scala.binary.version>$SHORT_SCALA_BINARY_VERSION</short.scala.binary.version>
      <spark.version>$SPARK_VERSION</spark.version>
   </properties>

</project>);

sub get_jar_name_and_version($) {
  my ($jar) = @_;
  #my ($jar_name, $jar_version) = ($jar =~ /^([\w\-\.]+)-((?:\d+\.)*\d+(?:-(?:\d|3f79e055|GA|M15|M20|b34|hadoop2|incubating|nohive|shaded-protobuf|tests)|\.(?:Final|RELEASE|Release|spark2))?)\.jar$/);
  my ($jar_name, $jar_version) = ($jar =~ /^([\w\-\.]+)-((?:\d+\.)*\d+(?:[-\.]\S+)?)\.jar$/);
  return ($jar_name, $jar_version);
}

sub eval_version($) {
  my ($version) = @_;
  my @vals_rev = ();
  while (defined $version && $version =~ /\d+/) {
    my $val = undef;
    ($val, $version) = ($version =~ /(\d+)(.*)$/);
    push @vals_rev, $val;
  }
  my @vals = reverse @vals_rev;
  my $val_version = 0;
  for (my $i=0; $i<=$#vals; $i++) {
    $val_version += $vals[$i] * 10**$i;
  }
  return $val_version;
}

sub get_group_and_artifact($$) {
  my ($line, $version) = @_;
  my ($group_id, $artifact_id) = ($line =~ /^$ENV{'HOME'}\/.m2\/repository\/(\S+)\/([^\/]+)\/$version/);
  $group_id =~ s#/#.#g;
  return ($group_id, $artifact_id);
}

my $jar_list = {};
#my $cmd = "ssh $SPARK_HOST \"$REMOTE_CMD\"";
my $cmd = "/home/preaudc/vendor-src/spark-maven-parent/src/main/scripts/readPOM.pl | grep -v spark-testing-base";
open(CMD, "$cmd |") or die "$!";
while (my $cmd_line = <CMD>) {
  chomp $cmd_line;
  my @path = split("/", $cmd_line);
  my $jar = $path[$#path];
  my $jar_lib = ($cmd_line =~ /spark/i) ? "spark" : "hadoop";
  my ($jar_name, $jar_version) = get_jar_name_and_version($jar);
  if (not defined $jar_list->{$jar_name}) {
    $jar_list->{$jar_name} = $jar_version;
  } elsif ($jar_lib eq "spark") {
    $jar_list->{$jar_name} = $jar_version if $jar_name ne "javax.inject";
  } elsif (eval_version($jar_version) > eval_version($jar_list->{$jar_name})) {
    $jar_list->{$jar_name} = $jar_version;
  }
}
close CMD;

#my $artifact_id = "jackson-core-asl";
#my $version = $jar_list->{$artifact_id};
#print "$artifact_id - $version\n";
#open(CMD, "ssh $SPARK_HOST \"unzip -q -c /opt/spark/jars/$artifact_id-$version.jar META-INF/MANIFEST.MF | grep ^Bundle-SymbolicName\" |") or die "$!";
#while (my $cmd_line = <CMD>) {
#  chomp $cmd_line;
#  print "$cmd_line\n";
#}
#close CMD;

my @dependencies = ();
foreach my $k (keys %$jar_list) {
  my $version = $jar_list->{$k};
  open(CMD, "find $ENV{'HOME'}/.m2/repository -type d -name \"$version\" -print0 | grep -FzZ \"$k/$version\" 2>/dev/null |") or die "$!";
  while (my $ps_line = <CMD>) {
    chomp $ps_line;
    if ($ps_line ne "") {
      my ($group_id, $artifact_id) = get_group_and_artifact($ps_line, $version);
      $artifact_id =~ s/_$SCALA_BINARY_VERSION$/_\${scala.binary.version}/;
      if ($group_id eq 'org.apache.hadoop') {
        $version =~ s/^$HADOOP_VERSION$/\${hadoop.version}/;
      } elsif ($group_id eq 'org.apache.spark') {
        $version =~ s/^$SPARK_VERSION$/\${spark.version}/;
      } elsif ($group_id eq 'org.scala-lang') {
        $version =~ s/^$SCALA_VERSION$/\${scala.version}/;
      }
      push @dependencies, ["$group_id.$artifact_id", $group_id, $artifact_id, $version];
    }
  }
  close CMD;
}

open(POM, '>', "pom.xml") or die "$!";
print POM "$pom_header\n";
foreach my $dependency (sort {$a->[0] cmp $b->[0]} @dependencies) {
  my (undef, $group_id, $artifact_id, $version) = @$dependency;
  print POM qq(         <dependency>
            <groupId>$group_id</groupId>
            <artifactId>$artifact_id</artifactId>
            <version>$version</version>
            <scope>provided</scope>
         </dependency>\n);
}
print POM "\n$pom_footer\n";
close POM;
