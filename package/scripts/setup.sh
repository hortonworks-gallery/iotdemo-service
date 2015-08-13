#!/bin/bash
INSTALL_DIR=$1
HOSTNAME=$2
PORT=$3

#AMBARI_HOST=`hostname -f`
#AMBARI_PORT=8080
#AMBARI_USER=admin
#AMBARI_PASS=admin
#AMBARI_CLUSTER=iotdemo

export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk.x86_64

cd $INSTALL_DIR/sedev 

#remove uneeded artifacts
rm -rf .git/ datascience/ phoenix_demo_db/ poc-artifacts/ se-cloud/ slider_setup/ coe/ oslaunch/ pmbench/ sedemo/ windows_hdp_installer/ hadoop-mini-clusters/ cloudlaunch/
cd demo-artifacts
rm -rf document_crawler/ opentsdb_demo/ solr_apache_access_logs/ solr_hbase_sparse_data_demo/ storm_demo/

cd storm_demo_2.2/storm_demo
source setup/bin/ambari_util.sh

#sed -i "s/host='sandbox.hortonworks.com:8080'/host='$AMBARI_HOST:$AMBARI_PORT'/g" user-env.sh
#sed -i "s/cluster='Sandbox'/cluster='$AMBARI_CLUSTER'/g" user-env.sh
#sed -i "s/user='admin'/user='$AMBARI_USER'/g" user-env.sh
#sed -i "s/pass='admin'/pass='$AMBARI_PASS'/g" user-env.sh


#make sure kafka, storm, falcon are out of maintenance mode
#curl -u $AMBARI_USER:$AMBARI_PASS -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Remove Falcon from maintenance mode"}, "Body": {"ServiceInfo": {"maintenance_state": "OFF"}}}' http://$AMBARI_HOST:$AMBARI_PORT/api/v1/clusters/$AMBARI_CLUSTER/services/FALCON
#curl -u $AMBARI_USER:$AMBARI_PASS -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Remove Kafka from maintenance mode"}, "Body": {"ServiceInfo": {"maintenance_state": "OFF"}}}' http://$AMBARI_HOST:$AMBARI_PORT/api/v1/clusters/$AMBARI_CLUSTER/services/KAFKA
#curl -u $AMBARI_USER:$AMBARI_PASS -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Remove Storm from maintenance mode"}, "Body": {"ServiceInfo": {"maintenance_state": "OFF"}}}' http://$AMBARI_HOST:$AMBARI_PORT/api/v1/clusters/$AMBARI_CLUSTER/services/STORM
#curl -u $AMBARI_USER:$AMBARI_PASS -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Remove Hbase from maintenance mode"}, "Body": {"ServiceInfo": {"maintenance_state": "OFF"}}}' http://$AMBARI_HOST:$AMBARI_PORT/api/v1/clusters/$AMBARI_CLUSTER/services/HBASE

#if Falcon is local and found to be running, kill it
if [ -e "/usr/hdp/current/falcon-server" ]
then
	FALCON_OFF=`/usr/hdp/current/falcon-server/bin/falcon-status` | grep "not running" | wc -l
	if $FALCON_OFF
	then
		/usr/hdp/current/falcon-server/bin/falcon-stop
		sleep 4
	fi	
fi

#if [ `check STORM STARTED` -ne 1 ] 
#then
#	echo 'Storm is not up. Please start Storm and try again'
#	exit 1
#fi

#if  [ `check KAFKA STARTED` -ne 1 ] 
#then
#	echo 'Kafka is not up. Please start Kafka and try again'
#	exit 1
#fi

#if  [ `check HBASE STARTED` -ne 1 ] 
#then
#	echo 'HBase is not up. Please start Hbase and try again'
#	exit 1
#fi
#if  [ `check FALCON STARTED` -ne 0 ]
#then
#	echo 'Falcon was found to be up. Please stop Falcon and try again'
#	exit 1
#fi

#start the installation
./installdemo.sh
source ~/.bashrc

cd storm-demo-webapp
cp -R routes /etc/storm_demo
#$INSTALL_DIR/maven/bin/mvn -DskipTests clean package

cd /root
git clone https://github.com/abajwa-hw/iframe-view.git
sed -i "s/iFrame View/IoT Demo/g" iframe-view/src/main/resources/view.xml   
sed -i "s/IFRAME_VIEW/IOTDEMO/g" iframe-view/src/main/resources/view.xml    
sed -i "s#sandbox.hortonworks.com:6080#$HOSTNAME:$PORT/storm-demo-web-app#g" iframe-view/src/main/resources/index.html    
sed -i "s/iframe-view/iotdemo-view/g" iframe-view/pom.xml   
sed -i "s/Ambari iFrame View/IoTDemo View/g" iframe-view/pom.xml    
mv iframe-view iotdemo-view
cd iotdemo-view
mvn clean package

