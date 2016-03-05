import sys, os, pwd, signal, time
from resource_management import *
from subprocess import call

class Master(Script):
  def install(self, env):
    # Install packages listed in metainfo.xml
    self.install_packages(env)

    import params

    #debug info
    
    #e.g /root/sedev/demo-artifacts/storm_demo_2.2/storm_demo     
    Execute('echo cloned scripts dir is: ' + params.scripts_dir) 
    
    Execute('echo list of config dump: ' + str(', '.join(params.list_of_configs)))    
    Execute('echo master config dump: ' + str(', '.join(params.master_configs)))
    
    Execute('echo ambari host: ' + params.ambari_server_host) 
    Execute('echo namenode host: ' + params.namenode_host)    
    Execute('echo nimbus host: ' + params.nimbus_host)
    Execute('echo hive metastore host: ' + params.hive_metastore_host)
    Execute('echo supervisor hosts: ' + params.supervisor_hosts)    
    Execute('echo hbase master host: ' + params.hbase_master_host)   
    Execute('echo kafka host: ' + params.kafka_broker_host)    
    Execute('echo activemq host: ' + params.activemq_host)    

    #Execute('echo kafka-broker dump: ' + str(', '.join(params.config['configurations']['kafka-broker'])))  
    Execute('echo demo port: ' + params.port)
    Execute('echo ambari port: ' + params.ambari_port)
    Execute('echo namenode port: ' + params.namenode_port)
    Execute('echo hive MS port: ' + params.hive_metastore_port)
    Execute('echo kafka port: ' + params.kafka_port)

    if params.use_public_git:
      Execute ('rm -rf ' + os.path.join(params.install_dir,'iot-truck-streaming') , ignore_failures=True)
      Execute ('cd ' + params.install_dir +'; git clone https://github.com/DhruvKumar/iot-truck-streaming >> '+params.stack_log)    
    else:
      #pull code
      Execute ('rm -rf ' + os.path.join(params.install_dir,'sedev') , ignore_failures=True)
      Execute ('echo "machine github.com login '+params.git_username+' password '+params.git_password+'" > /root/.netrc')
      Execute ('cd ' + params.install_dir +'; git clone https://github.com/hortonworks/sedev >> '+params.stack_log)
      #Execute ('export GIT_USER="'+params.git_username+'" ; export GIT_PASS="'+params.git_password+'"; cd ' + params.install_dir +'; git clone https://$GIT_USER:$GIT_PASS@github.com/hortonworks/sedev >> '+params.stack_log)

    #update configs
    self.configure(env)
    
    
    Execute('rm -f /root/.netrc')
    
  def configure(self, env):
    import params
    import status_params    
    env.set_params(params)
    
    content=InlineTemplate(status_params.demo_template_config)
    File(format("{scripts_dir}/config.properties"), content=content, owner='root',group='root', mode=0666)

    ambari_content=InlineTemplate(params.user_env)
    File(format("{scripts_dir}/user-env.sh"), content=ambari_content, owner='root',group='root', mode=0777)

  def stop(self, env):
    import params  
    import status_params
    import time
        
    env.set_params(status_params)
    self.configure(env)
    
    #kill webapp
    
    #kill child processes if exists
    Execute (format('pkill -TERM -P `cat {stack_pidfile}` >/dev/null 2>&1'), ignore_failures=True)
    #kill process
    Execute (format('kill `cat {stack_pidfile}` >/dev/null 2>&1')) 
    #remove pid file
    Execute (format("rm -f {stack_pidfile}"))
    
    #kill activemq
    Execute('/opt/activemq/latest/bin/activemq stop')
    
    #kill topology
    Execute('storm kill truck-event-processor -c nimbus.host=' + params.nimbus_host)
    
    #wait for topology to come down
    time.sleep(30)
          
  def start(self, env):
    import params
    import status_params
    self.configure(env)

    if not os.path.exists(status_params.stack_piddir):
      os.makedirs(status_params.stack_piddir)

    if not os.path.exists(params.scripts_dir + '/storm-streaming/target/storm-streaming-1.0-SNAPSHOT.jar'):
      # first time run
      if params.use_public_git:    
        install_script = os.path.join(params.service_scriptsdir,'setup.sh')
      else:
        install_script = os.path.join(params.service_scriptsdir,'setup_private.sh')      
      Execute ('chmod +x ' + install_script)
      Execute(install_script + ' "'+ params.install_dir + '" "' + params.public_host + '" "' + params.port + '" "' + params.jdk64_home + '" >> ' + params.stack_log)
    
      #if iotdemo installed on ambari server, copy view jar into ambari views dir
      if params.ambari_host == params.internal_host and not os.path.exists('/var/lib/ambari-server/resources/views/iotdemo-view-1.0-SNAPSHOT.jar'):
        Execute('echo "Copying iodemo view jar to ambari views dir"')      
        Execute('/bin/cp -f /root/iotdemo-view/target/*.jar /var/lib/ambari-server/resources/views')
    
    
    nimbus_host = str(params.master_configs['nimbus_hosts'][0])
    
    #start active mq
    Execute('/opt/activemq/latest/bin/activemq start xbean:file:/opt/activemq/latest/conf/activemq.xml >> '+params.stack_log)

    #if ranger found start it
    Execute('if [ `ls /etc/init.d | grep ranger-admin | wc -l` ]; then service ranger-admin start; fi', ignore_failures=True)
    
    #if ranger-solr found, start it
    if os.path.exists('/opt/solr/ranger_audit_server/scripts/start_solr.sh'):
      Execute('/opt/solr/ranger_audit_server/scripts/start_solr.sh', ignore_failures=True)            
      
    #start jetty app  
    Execute ('cd '+params.scripts_dir+'; storm jar storm-streaming/target/storm-streaming-1.0-SNAPSHOT.jar com.hortonworks.streaming.impl.topologies.TruckEventProcessorKafkaTopology /etc/storm_demo/config.properties -c nimbus.host=' + nimbus_host + ' >> '+params.stack_log)
    webapp_dir=os.path.join(params.scripts_dir,'storm-demo-webapp')
    start_cmd='cd ' + webapp_dir + '; '+params.install_dir+'/maven/bin/mvn jetty:run -Djetty.port=' + params.port + ' ; '      
    Execute('nohup sh -c "'+start_cmd+'" >> '+params.stack_log+' 2>&1 & echo $! > ' + status_params.stack_pidfile)
	

  def status(self, env):
    import status_params
    env.set_params(status_params)  
    check_process_status(status_params.stack_pidfile)    

    
if __name__ == "__main__":
  Master().execute()
