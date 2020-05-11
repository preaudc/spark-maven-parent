#!/usr/bin/perl

use Getopt::Long;
use strict;
use warnings;

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

my $pom_header = qq(<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">

   <!-- PROJECT DESCRIPTION SECTION -->
   <modelVersion>4.0.0</modelVersion>
   <groupId>my.group.id</groupId>
   <artifactId>sparkMavenParent</artifactId>
   <version>1.0.0</version>
   <packaging>pom</packaging>
   <name>sparkMavenParent</name>
   <description>Parent POM for Spark applications components</description>

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

sub printUsage() {
  print STDERR "Usage:\n\t$0 -hostname HOSTNAME\n";
  exit 1;
}

my $hostname = undef;
printUsage() unless (GetOptions("hostname=s" => \$hostname) and defined $hostname);

my $jar_list = {};
my $cmd = "ssh $hostname \"$REMOTE_CMD\"";
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

open(POM, '>', "pom.xml.template") or die "$!";
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
