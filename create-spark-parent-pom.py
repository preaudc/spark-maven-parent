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

@total_ordering
class JarVersion:
    def __init__(self, version):
        self.version = version

    def __lt__(self, other):
        return self._eval_version() < other._eval_version() or (
            self._eval_version() == other._eval_version() and
                len(self.version) > len(other.version)
        )

    def _eval_version(self):
        version_parts = re.match(r'(\d+)(?:\.(\d+)(?:\.(\d+)(?:\.(\d+))?)?)?', self.version).groups()
        val_version = 0
        for i in range(len(version_parts)):
            if version_parts[i] is not None:
                val_version += int(version_parts[i]) * 10**(len(version_parts)-i-1)
        return val_version

def get_dependencies(jar_list, provided):
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
            dependencies.append(f'''      <dependency>
         <groupId>{jar_deps['group_id']}</groupId>
         <artifactId>{jar_deps['artifact_id']}</artifactId>
         <version>{jar_deps['version']}</version>
      </dependency>''')
    return "\n".join(dependencies)

def get_group(version, jar_name, jar_path, conf):
    if re.match(r'^spark-', jar_name):
        jar_group = conf['spark_group_id']
    elif re.match(r'^hadoop-', jar_name):
        jar_group = conf['hadoop_group_id']
    else:
        jar_group = get_group_from_m2_repo(jar_path, conf)
        if jar_group is None:
            jar_group = get_group_from_mvn_ws(jar_path, conf)
    return jar_group

# get group from ~/.m2 repository
def get_group_from_m2_repo(jar_path, conf):
    jar_name = Path(jar_path).name
    m2_path = Path.home() / '.m2' / 'repository'
    m2_jars = dict(map(lambda p: (sha1sum(p), p), m2_path.glob(f'**/{jar_name}')))
    jar_sha1 = sha1sum(jar_path)
    if jar_sha1 in m2_jars:
        group_parts = m2_jars[jar_sha1].parts
        group = '.'.join(group_parts[len(m2_path.parts):len(group_parts)-3])
        return group

# get group from maven search central WS
def get_group_from_mvn_ws(jar_path, conf):
    time.sleep(1)
    jar_group = None
    parameters = {
        'q': f'1:"{sha1sum(jar_path)}"',
        'rows': '20',
        'wt': 'json'
    }
    r = requests.get(conf['mvn_search_url'], params=parameters)
    r.raise_for_status()
    json_response = r.json()
    if json_response['response']['docs']:
        jar_group = json_response['response']['docs'][0]['g']
    else:
        print(f'WARN Cannot find group id for {jar_path} --> Excluded from POM!')
    return jar_group

def get_jar_list(jar_file, conf):
    jar_list = {}
    for jar in read_jars(jar_file):
        jar_path = Path(jar)
        jar_name, jar_version = get_jar_name_and_version(jar_path.name)
        if jar_name in jar_list and jar_list[jar_name]['group_id'] not in conf['static_group_version']:
            if JarVersion(jar_version) > JarVersion(jar_list[jar_name]['version']):
                jar_group = get_group(jar_version, jar_name, jar_path, conf)
                jar_list[jar_name]['group_id'] = jar_group
                jar_list[jar_name]['version'] = jar_version
        else:
            jar_group = get_group(jar_version, jar_name, jar_path, conf)
            if jar_group is not None:
                jar_list[jar_name] = {
                    'group_id': jar_group,
                    'artifact_id': replace_artifact_suffix(jar_name, conf),
                    'version': set_version(jar_version, jar_group, conf)
                }
    return jar_list

def get_jar_name_and_version(jar_path):
    pattern = re.compile(r'^([\w\-\.]+?)-((?:\d+\.)*\d+(?:[-\.]\S+)?)\.jar$')
    return pattern.match(jar_path).groups()

def load_config(conf_path) -> dict:
    with open(conf_path) as f:
        conf = yaml.safe_load(f)
    return conf

def parse_args() -> dict:
    parser = argparse.ArgumentParser(description='Create Maven POM to package Spark libraries.')
    parser.add_argument('input_file', metavar='FILE', help='input file containing jars path')
    parser.add_argument('--provided', action='store_true', help='set dependencies as provided')
    parser.add_argument('--output_file', help='output POM file')
    return parser.parse_args()

def read_jars(path) -> dict:
    try:
        with open(path) as f:
            jars = f.readlines()
    except FileNotFoundError as e:
        sys.exit(f'ERROR: {e}')
    return map(lambda jar: jar.rstrip('\n'), jars)

def replace_artifact_suffix(jar_property, conf):
    for orig_key, replace_key in conf['artifact_suffix'].items():
        return re.sub(f'{orig_key}$', f'{replace_key}', jar_property)

def set_version(jar_version, jar_group, conf):
    if jar_group in conf['static_group_version']:
        return conf['static_group_version'][jar_group]
    else:
        return jar_version

def write_pom(jar_list, args, conf):
    if args.output_file:
        with open(args.output_file, 'w') as f:
            print(eval(conf['pom_header']), file=f)
            print(get_dependencies(jar_list, args.provided), file=f)
            print(eval(conf['pom_footer']), file=f)
        f.close()
    else:
        print(get_dependencies(jar_list, args.provided))

def main(argv):
    args = parse_args()

    # read configuration file
    cmd_path = Path(argv[0])
    conf = load_config(f'{cmd_path.parent}/{cmd_path.stem}.yaml')

    jar_list = get_jar_list(args.input_file, conf)
    write_pom(jar_list, args, conf)

def sha1sum(filename):
    h  = hashlib.sha1()
    b  = bytearray(128*1024)
    mv = memoryview(b)
    with open(filename, 'rb', buffering=0) as f:
        for n in iter(lambda : f.readinto(mv), 0):
            h.update(mv[:n])
    return h.hexdigest()

main(sys.argv)
