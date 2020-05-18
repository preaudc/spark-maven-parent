#!/usr/bin/perl

use Getopt::Long;
use strict;
use warnings;

## BEGIN - CUSTOM CONF
# pom properties
my $HADOOP_VERSION = "2.8.3";
my $JDK_VERSION = "1.8";
my $SCALA_BINARY_VERSION = "2.12";
my $SCALA_VERSION = "2.12.10";
my $SPARK_VERSION = "2.4.5";
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

my $pom_footer = qq(      </dependencies>
   </dependencyManagement>

   <!-- PROPERTIES SECTION -->
   <properties>
      <hadoop.version>$HADOOP_VERSION</hadoop.version>
      <jdk.version>$JDK_VERSION</jdk.version>
      <scala.binary.version>$SCALA_BINARY_VERSION</scala.binary.version>
      <scala.version>$SCALA_VERSION</scala.version>
      <spark.version>$SPARK_VERSION</spark.version>
   </properties>

</project>);

my $hadoop_group_id = "org.apache.hadoop";
my $mvn_search_url = "http://search.maven.org/solrsearch/select";
my $scala_group_id = "org.scala-lang";
my $spark_group_id = "org.apache.spark";

sub get_jar_name_and_version($) {
  my ($jar) = @_;
  my ($jar_name, $jar_version) = ($jar =~ /^([\w\-\.]+?)-((?:\d+\.)*\d+(?:[-\.]\S+)?)\.jar$/);
  return ($jar_name, $jar_version);
}

# function to compare jar versions
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

# get group and artifact id from jar path in $HOME/.m2 repository
sub get_group_and_artifact($$$) {
  my ($version, $jar_name, $jar_path) = @_;
  my ($group_id, $artifact_id);
  if ($jar_name =~ /^spark-/) {
    ($group_id, $artifact_id) = ($spark_group_id, $jar_name);
  } elsif ($jar_name =~ /^hadoop-/) {
    ($group_id, $artifact_id) = ($hadoop_group_id, $jar_name);
  } elsif ($jar_name =~ /^scala-/ && $jar_name !~ /_$SCALA_BINARY_VERSION$/) {
    ($group_id, $artifact_id) = ($scala_group_id, $jar_name);
  } else {
    my $find_line = qx(find $ENV{'HOME'}/.m2/repository -type d -name "$version" -print0 | grep -FzZ "$jar_name/$version" 2>/dev/null);
    chomp $find_line;
    if ($find_line ne "") {
      ($group_id, $artifact_id) = ($find_line =~ /^$ENV{'HOME'}\/.m2\/repository\/(\S+)\/([^\/]+)\/$version/);
      $group_id =~ s#/#.#g;
    } elsif (-f $jar_path) {
      $artifact_id = $jar_name;
      $group_id = qx/curl -s "$mvn_search_url?q=1:%22\$(sha1sum $jar_path | awk '{print \$1}')%22&rows=20&wt=json" | jq -M -r '.response.docs[0].g'/;
      chomp $group_id;
      if ($group_id eq "null") {
        ($group_id, $artifact_id) = (undef, undef);
      }
    }
  }
  return ($group_id, $artifact_id);
}

# print usage
sub printUsage() {
  print STDERR "Usage:\n\t$0 -file JARS_FILE\n";
  exit 1;
}

my $jars_file = undef;
printUsage() unless (GetOptions("file=s" => \$jars_file) and defined $jars_file);

# get the list of jars with version, dedup if necessary (priority on Spark version, then higher version)
my $jar_list = {};
open(FILE, "$jars_file") or die "$jars_file: $!";
foreach my $jar_path (sort {$a =~ /\/spark\//i <=> $b =~ /\/spark\//i} <FILE>) {
  chomp $jar_path;
  my @path = split("/", $jar_path);
  my $jar = $path[$#path];
  my ($jar_name, $jar_version) = get_jar_name_and_version($jar);
  if (not defined $jar_list->{$jar_name}) {
    $jar_list->{$jar_name} = [$jar_path, $jar_version];
  } elsif ($jar_path =~ /spark/i) {
    $jar_list->{$jar_name} = [$jar_path, $jar_version] if $jar_name ne "javax.inject";
  } elsif (eval_version($jar_version) > eval_version($jar_list->{$jar_name}->[1])) {
    $jar_list->{$jar_name} = [$jar_path, $jar_version];
  }
}
close FILE;

# loop on each jar to get group id, artifact id and version
my @dependencies = ();
foreach my $jar_name (keys %$jar_list) {
  my ($jar_path, $version) = @{$jar_list->{$jar_name}};
  my ($group_id, $artifact_id) = get_group_and_artifact($version, $jar_name, $jar_path);
  if (defined $group_id and defined $artifact_id) {
    $artifact_id =~ s/_$SCALA_BINARY_VERSION$/_\${scala.binary.version}/;
    if ($group_id eq $hadoop_group_id) {
      $version =~ s/^$HADOOP_VERSION$/\${hadoop.version}/;
    } elsif ($group_id eq $spark_group_id) {
      $version =~ s/^$SPARK_VERSION$/\${spark.version}/;
    } elsif ($group_id eq $scala_group_id) {
      $version =~ s/^$SCALA_VERSION$/\${scala.version}/;
    }
    push @dependencies, ["$group_id.$artifact_id", $group_id, $artifact_id, $version];
  } else {
    print STDERR "WARN Cannot find groupId for $jar_name-$version --> Excluded from POM!\n";
  }
}

# print POM template
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
print POM "$pom_footer\n";
close POM;
