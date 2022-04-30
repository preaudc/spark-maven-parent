#!/usr/bin/perl

use XML::LibXML::Simple ();

use strict;
use warnings;

my $m2_dir = "/home/preaudc/.m2/repository";
my $pom = "/home/preaudc/data-platform/kelkooSparkMavenParent/pom.xml";

my $xs = XML::LibXML::Simple->new();
my $data = $xs->XMLin($pom);

my $properties = $data->{'properties'};
#foreach my $property (keys %$properties) {
#  print "$property: $properties->{$property}\n";
#}

my $dependencies = $data->{'dependencyManagement'}->{'dependencies'}->{'dependency'};
foreach my $dependency (@$dependencies) {
  my $group_id = $dependency->{'groupId'};
  $group_id =~ s#\.#/#g;
  my $artifact_id = $dependency->{'artifactId'};
  $artifact_id =~ s/\$\{([^\}]+)\}/$properties->{$1}/;
  my $version = $dependency->{'version'};
  $version =~ s/\$\{([^\}]+)\}/$properties->{$1}/g;
  print "$m2_dir/$group_id/$artifact_id/$version/$artifact_id-$version.jar\n";
}
