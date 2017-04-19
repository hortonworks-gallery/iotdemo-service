#!/usr/bin/env python
from resource_management import *

config = Script.get_config()

stack_piddir = config['configurations']['demo-env']['demo_piddir']
stack_pidfile = format("{stack_piddir}/demo-env.pid")
demo_template_config = config['configurations']['demo-env']['content']


#read cluster info - these values will be replaced added to demo-env.xml at runtime
#master_configs = config['clusterHostInfo']
#ambari_server_host = str(master_configs['ambari_server_host'][0])
