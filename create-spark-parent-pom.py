#!/usr/bin/python3

import argparse
import hashlib
import re
import requests
import sys
import time
import yaml

from functools import total_ordering
from pathlib import Path

class ArgParser:
    def parse_args() -> dict:
        parser = argparse.ArgumentParser(description='Create Maven POM to package Spark libraries.')
        parser.add_argument('input_file', metavar='FILE', help='input file containing jars path')
        parser.add_argument('--provided', action='store_true', help='set dependencies as provided')
        parser.add_argument('--output-file', help='output POM file')
        return parser.parse_args()

class ConfLoader:
    def load_config(cmd_path, jars_path) -> dict:
        conf_path = f'{cmd_path.parent}/conf/{cmd_path.stem}.yaml'
        with open(conf_path) as f:
            conf = yaml.safe_load(f)
            ## set configuration properties from jars in input file
            conf['properties_version'] |= {'scala_binary_version': PomUtils.get_scala_binary_version(jars_path, conf['properties_jar']['spark_version'])}
            for prop in ['hadoop_version', 'scala_version', 'spark_version']:
                conf['properties_version'] |= {prop: PomUtils.get_jar_version(jars_path, conf['properties_jar'][prop])}
            conf |= {'artifact_suffix': {f"_{conf['properties_version']['scala_binary_version']}": '_${scala.binary.version}'}}
        return conf

class PomUtils:
    def has_higher_priority_in_pom(this_jar_priority, this_jar_version, other_jar):
        return (this_jar_priority >= other_jar['priority'] and
            JarVersion(this_jar_version) > JarVersion(other_jar['version']))

    # get group from local maven repository
    def get_group_from_m2_repo(jar_path):
        jar_name = Path(jar_path).name
        m2_path = Path.home() / '.m2' / 'repository'
        m2_jars = dict(map(lambda p: (sha1sum(p), p), m2_path.glob(f'**/{jar_name}')))
        jar_sha1 = sha1sum(jar_path)
        if jar_sha1 in m2_jars:
            group_parts = m2_jars[jar_sha1].parts
            group = '.'.join(group_parts[len(m2_path.parts):len(group_parts)-3])
            return group

    # get group from maven search central WS
    def get_group_from_mvn_ws(mvn_search_url, jar_path):
        time.sleep(1)
        print(f'using {mvn_search_url} for {jar_path}');
        jar_group = None
        parameters = {
            'q': f'1:"{sha1sum(jar_path)}"',
            'rows': '20',
            'wt': 'json'
        }
        r = requests.get(mvn_search_url, params=parameters)
        r.raise_for_status()
        json_response = r.json()
        if json_response['response']['docs']:
            jar_group = json_response['response']['docs'][0]['g']
        else:
            print(f'WARN Cannot find group id for {jar_path} --> Excluded from POM!')
        return jar_group

    def get_jar_name_and_version_from_jar_prefix(jars_path, jar_prefix):
        return PomUtils.get_jar_name_and_version_from_path(
            next(
                filter(
                    lambda jar_name: jar_name.startswith(jar_prefix),
                    map(lambda jar: Path(jar).name, jars_path)
                )
            )
        )

    def get_jar_name_and_version_from_path(jar_path):
        pattern = re.compile(r'^([\w\-\.]+?)-((?:\d+\.)*\d+(?:[-\.]\S+)?)\.jar$')
        return pattern.match(jar_path).groups()

    def get_jar_version(jars_path, jar_prefix):
        _, jar_version = PomUtils.get_jar_name_and_version_from_jar_prefix(jars_path, jar_prefix)
        return jar_version

    def get_scala_binary_version(jars_path, jar_prefix):
        jar_name, _ = PomUtils.get_jar_name_and_version_from_jar_prefix(jars_path, jar_prefix)
        return jar_name.removeprefix(f'{jar_prefix}_')

    def replace_artifact_suffix(artifact_suffix_map, jar_property):
        for orig_key, replace_key in artifact_suffix_map.items():
            return re.sub(f'{orig_key}$', f'{replace_key}', jar_property)

@total_ordering
class JarVersion:
    def __init__(self, version):
        self.version = version

    def __eq__(self, other):
        return self._eval_version() == other._eval_version()

    def __gt__(self, other):
        return self._eval_version() > other._eval_version()

    def _eval_version(self):
        version_parts = list(filter(lambda part: re.match(r'^\d+$', part), re.split(r'(\d+)', self.version)))
        val_version = 0
        for i in range(len(version_parts)):
            if version_parts[i] is not None:
                val_version += int(version_parts[i]) * 10**(len(version_parts)-i-1)
        return val_version

class SparkParentPom:
    def __init__(self):
        self.args = ArgParser.parse_args()

    def load_config(self, argv, jars_path):
        # read configuration file
        cmd_path = Path(argv[0])
        self.conf = ConfLoader.load_config(cmd_path, jars_path)

    def get_jar_list(self, jars_path):
        jar_list = {}
        for jar in jars_path:
            jar_path = Path(jar)
            jar_name, jar_version = PomUtils.get_jar_name_and_version_from_path(jar_path.name)
            jar_priority = self.conf['parent_priority'][jar_path.parts[1]]
            if jar_name in jar_list and jar_list[jar_name]['group_id'] not in self.conf['static_group_version']:
                if PomUtils.has_higher_priority_in_pom(jar_priority, jar_version, jar_list[jar_name]):
                    print(f"{jar_path} - {jar_name} --> {jar_version} - {jar_list[jar_name]['version']}")
                    jar_group = self.__get_group(jar_version, jar_name, jar_path)
                    jar_list[jar_name]['group_id'] = jar_group
                    jar_list[jar_name]['version'] = jar_version
            else:
                jar_group = self.__get_group(jar_version, jar_name, jar_path)
                if jar_group is not None:
                    jar_list[jar_name] = {
                        'priority': self.conf['parent_priority'][jar_path.parts[1]],
                        'group_id': jar_group,
                        'artifact_id': PomUtils.replace_artifact_suffix(self.conf['artifact_suffix'], jar_name),
                        'version': self.__set_version(jar_version, jar_group)
                    }
        return jar_list

    def write_pom(self, jar_list, args):
        if args.output_file:
            with open(args.output_file, 'w') as f:
                for line in self.conf['pom_header']:
                    print(eval(line), file=f)
                print(self.__get_dependencies(jar_list, args.provided), file=f)
                for line in self.conf['pom_footer']:
                    print(eval(line), file=f)
            f.close()
        else:
            print(self.__get_dependencies(jar_list, args.provided))

    def __get_dependencies(self, jar_list, provided):
        dependencies=[]
        for jar_name, jar_deps in sorted(jar_list.items(), key=lambda item: f'''{item[1]['group_id']}.{item[1]['artifact_id']}'''):
            if provided:
                dependencies.append(f'''         <dependency>
            <groupId>{jar_deps['group_id']}</groupId>
            <artifactId>{jar_deps['artifact_id']}</artifactId>
            <version>{jar_deps['version']}</version>
            <scope>provided</scope>
         </dependency>''')
            else:
                dependencies.append(f'''         <dependency>
            <groupId>{jar_deps['group_id']}</groupId>
            <artifactId>{jar_deps['artifact_id']}</artifactId>
            <version>{jar_deps['version']}</version>
         </dependency>''')
        return "\n".join(dependencies)

    def __get_group(self, version, jar_name, jar_path):
        if re.match(r'^spark-', jar_name):
            jar_group = self.conf['spark_group_id']
        elif re.match(r'^hadoop-', jar_name):
            jar_group = self.conf['hadoop_group_id']
        else:
            jar_group = PomUtils.get_group_from_m2_repo(jar_path)
            if jar_group is None:
                jar_group = PomUtils.get_group_from_mvn_ws(self.conf['mvn_search_url'], jar_path)
        return jar_group

    def __set_version(self, jar_version, jar_group):
        if jar_group in self.conf['static_group_version']:
            return self.conf['static_group_version'][jar_group]
        else:
            return jar_version

def read_jars(input_file) -> dict:
    try:
        with open(input_file) as f:
            jars = f.readlines()
    except FileNotFoundError as e:
        sys.exit(f'ERROR: {e}')
    return list(map(lambda jar: jar.rstrip('\n'), jars))

def sha1sum(filename):
    h  = hashlib.sha1()
    b  = bytearray(128*1024)
    mv = memoryview(b)
    with open(filename, 'rb', buffering=0) as f:
        for n in iter(lambda : f.readinto(mv), 0):
            h.update(mv[:n])
    return h.hexdigest()

def main(argv):
    spm = SparkParentPom()
    jars_path = read_jars(spm.args.input_file)
    spm.load_config(argv, jars_path)
    jar_list = spm.get_jar_list(jars_path)
    spm.write_pom(jar_list, spm.args)

main(sys.argv)
