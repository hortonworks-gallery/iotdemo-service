#!/usr/bin/env python
from resource_management import *
import os

def get_port_from_url(address):
  if not is_empty(address):
    return address.split(':')[-1]
  else:
    return address
    
# server configurations
config = Script.get_config()

stack_version_unformatted = config['hostLevelParams']['stack_version']

# e.g. /var/lib/ambari-agent/cache/stacks/HDP/2.2/services/iotdemo-service/package/scripts
service_scriptsdir = os.path.realpath(__file__).split('/scripts')[0] + '/scripts/'

install_dir = config['configurations']['demo-config']['demo.install_dir']
install_script = config['configurations']['demo-config']['demo.install_script']
stack_log = config['configurations']['demo-config']['demo.log']
git_username = config['configurations']['demo-config']['demo.git_username']
git_password = config['configurations']['demo-config']['demo.git_password']
port = str(config['configurations']['demo-config']['demo.port'])
public_host = config['configurations']['demo-config']['demo.host_publicname']
use_public_git = config['configurations']['demo-config']['demo.use_public_git']
mvn_home = config['configurations']['demo-config']['demo.mvn_home']
num_events = str(config['configurations']['demo-config']['demo.num_events'])

master_configs = config['clusterHostInfo']
ambari_host = str(master_configs['ambari_server_host'][0])
internal_host = str(master_configs['iotdemo_master_hosts'][0])

#scripts_path = config['configurations']['demo-config']['demo.scripts_path']
if use_public_git:
  scripts_path = 'iot-truck-streaming'
else:
  scripts_path = 'sedev/demo-artifacts/storm_demo_2.2/storm_demo'    

#if user did not specify public hostname of demo node, proceed with internal name instead
if public_host.strip() == '': 
  public_host = internal_host
  

scripts_dir = os.path.join(install_dir, scripts_path)
webapp_dir = install_dir + '/hdp/reference-apps/iot-trucking-app/trucking-web-portal'

#read user-env.xml settings entered by user
user_env = config['configurations']['user-env']['content']

welcome_env = config['configurations']['welcome-env']['content']

#read cluster info - these values will be replaced added to demo-env.xml at runtime
master_configs = config['clusterHostInfo']
ambari_server_host = str(master_configs['ambari_server_host'][0])
#namenode_host =  str(master_configs['namenode_host'][0])
#namenode_port = get_port_from_url(config['configurations']['core-site']['fs.defaultFS']) #8020
nimbus_host = str(master_configs['nimbus_hosts'][0])
#hive_metastore_host = str(master_configs['hive_metastore_host'][0])
#hive_metastore_port = get_port_from_url(config['configurations']['hive-site']['hive.metastore.uris']) #"9083"
supervisor_hosts = str(', '.join(master_configs['supervisor_hosts']))
nifi_host = str(master_configs['nifi_master_hosts'][0])
hbase_zookeeper = config['configurations']['hbase-site']['hbase.zookeeper.quorum']
kafka_broker_host = str(master_configs['kafka_broker_hosts'][0])
if 'port' in config['configurations']['kafka-broker']:
  kafka_port = str(config['configurations']['kafka-broker']['port'])
else:
  kafka_port = get_port_from_url(config['configurations']['kafka-broker']['listeners'])

#activemq_host = kafka_broker_host
activemq_host = internal_host
  
list_of_configs = config['configurations']

jdk64_home=config['hostLevelParams']['java_home']
