#!/bin/bash
export demo_root=$1
export HOSTNAME=$2
export PORT=$3
export JAVA_HOME=$4

#AMBARI_HOST=`hostname -f`
#AMBARI_PORT=8080
#AMBARI_USER=admin
#AMBARI_PASS=admin
#AMBARI_CLUSTER=iotdemo

echo "JAVA_HOME is $JAVA_HOME"



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



cd ${demo_root}

sudo yum -y groupinstall "Development Tools"
sudo yum install -y wget git

echo "setup Python..."
wget http://www.python.org/ftp/python/3.3.2/Python-3.3.2.tar.bz2 -O /var/tmp/Python-3.3.2.tar.bz2
bzip2 -cd /var/tmp/Python-3.3.2.tar.bz2 | tar xvf -
cd Python-3.3.2
./configure
make
sudo make install
sudo ln -s /usr/local/bin/python3 /usr/bin/python3
python3 --version

echo "Setup maven..."
wget http://mirror.cc.columbia.edu/pub/software/apache/maven/maven-3/3.0.5/binaries/apache-maven-3.0.5-bin.tar.gz
sudo tar xzf apache-maven-3.0.5-bin.tar.gz -C /usr/local
cd /usr/local
sudo ln -s apache-maven-3.0.5 maven
export M2_HOME=/usr/local/maven
export PATH=${M2_HOME}/bin:${PATH}
echo 'M2_HOME=/usr/local/maven' >> ~/.bashrc
echo 'M2=$M2_HOME/bin' >> ~/.bashrc
echo 'PATH=$PATH:$M2' >> ~/.bashrc

echo "Setup npm..."
sudo yum install npm --enablerepo=epel -y
sudo npm install npm -g
sudo npm install -g grunt-cli
sudo npm install bower -g


echo "Setup activemq..."
sudo mkdir /opt/activemq
cd /opt/activemq
sudo wget http://archive.apache.org/dist/activemq/apache-activemq/5.9.0/apache-activemq-5.9.0-bin.tar.gz
sudo tar xvzf apache-activemq-*.tar.gz
sudo ln -s apache-activemq-5.9.0 latest


echo "Setup kafka..."
cd /usr/hdp/current/kafka-broker/bin
./kafka-topics.sh --create --zookeeper $(hostname -f):2181 --replication-factor 1 --partition 5 --topic truck_speed_events
./kafka-topics.sh --create --zookeeper $(hostname -f):2181 --replication-factor 1 --partition 5 --topic truck_events
./kafka-topics.sh --zookeeper $(hostname -f):2181 --list

echo "Setup HBase..."
echo "create 'driver_dangerous_events', {NAME=> 'events', VERSIONS=>3}" | hbase shell
echo "create 'driver_dangerous_events_count', {NAME=> 'counters', VERSIONS=>3}" | hbase shell
echo "create 'driver_events', {NAME=> 'allevents', VERSIONS=>3}" | hbase shell



#update configs
update_config () {
  output=`curl -u admin:admin -i -H 'X-Requested-By: ambari'  http://localhost:8080/api/v1/clusters`
  cluster_name=`echo $output | sed -n 's/.*"cluster_name" : "\([^\"]*\)".*/\1/p'`
  export HOST=$(hostname -f)
  

  sed -i "s|\(ambari.cluster.name\)=.*|\1=${cluster_name}|" $1
  sed -i "s|\(ambari.server.url\)=.*|\1=http://${HOST}:8080/|" $1
  sed -i "s|\(hbase.zookeeper.host\)=.*|\1=${HOST}|" $1
  sed -i "s|\(trucking.notification.topic.connection.url\)=.*|\1=tcp://${HOST}:61616|" $1
  sed -i "s|\(trucking.activemq.host\)=.*|\1=${HOST}|" $1
  sed -i "s|/Users/gvetticaden|${HOME}|" $1
}

cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-storm-topology/src/main/resources/config/dev/registry/
cp trucking-streaming-hdp-service-config.properties trucking-streaming-hdp-service-config.properties.orig
update_config trucking-streaming-hdp-service-config.properties

cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-web-portal/src/main/resources/config/dev/registry/
cp ref-app-hdp-service-config.properties ref-app-hdp-service-config.properties.orig
update_config ref-app-hdp-service-config.properties

#change links on trucking demo webapp home page
#for sandbox, change to: sandbox.hortonworks.com
#otherwise use public IP (required for cloud deployments)
export public_ip=$(curl icanhazip.com)
export hostname=$(hostname -f)

if [ "${hostname}" = "sandbox.hortonworks.com" ]; then
    export webui_host=${hostname}
else
    export webui_host=${public_ip}
fi

cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-web-portal/src/main/webappResources/views
cp welcome.html welcome.html.orig
sed -i "s|http://hdf.*\.com|http://${webui_host}|" welcome.html


#install bower
cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-web-portal
bower install --allow-root


#build hdp-app-utils 
cd ${demo_root}/hdp/app-utils/hdp-app-utils 
mvn clean install -DskipTests=true


#Build iot-trucking-app
cd ${demo_root}/hdp/reference-apps/iot-trucking-app 
mvn clean install -DskipTests=true
# With george's latest code, this step failing with: Failure to find com.hortonworks.registries:schema-registry-serdes:jar:0.1.0-SNAPSHOT
# make sure pom for trucking-web-portal has org.ow2.asm dependencies

cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-data-simulator
mvn assembly:assembly


#install latest storm view jar
cd /var/lib/ambari-server/resources/views/
rm -f storm-view-2.*.jar
wget https://hipchat.hortonworks.com/files/1/1907/zF4FiDbf3sMXsjy/storm-view-0.1.0.0.jar
chmod 777 storm-view-0.1.0.0.jar

#Instantiate Storm view
source /root/ambari-bootstrap/extras/ambari_functions.sh
ambari_configs

read -r -d '' body <<EOF
{
  "ViewInstanceInfo": {
    "instance_name": "StormAdmin", "label": "Storm View", "description": "Storm View",
    "visible": true,
    "properties": {
      "storm.host" : "$(hostname -f)",
      "storm.port" : "8744"
    }
  }
}
EOF
${ambari_curl}/views/Storm_Monitoring/versions/0.1.0/instances/StormAdmin -X DELETE
echo "${body}" | ${ambari_curl}/views/Storm_Monitoring/versions/0.1.0/instances/StormAdmin -X POST -d @-

#need to do this outside Ambari
#clear views work dir and restart Ambari
#rm -rf work*
#ambari-server restart
#sleep 15

#update storm jar in storm lib dir
#mkdir ${demo_root}/oldjars
#mv /usr/hdp/2.5.0.0-1245/storm/lib/log4j*-2.1.jar ${demo_root}/oldjars
#cp ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-data-simulator/target/log4j*-2.6.2.jar /usr/hdp/2.5.0.0-1245/storm/lib/


echo "Starting view compile..."
cd /root
rm -rf iframe-view
git clone https://github.com/abajwa-hw/iframe-view.git
sed -i "s/iFrame View/IoT Demo/g" iframe-view/src/main/resources/view.xml   
sed -i "s/IFRAME_VIEW/IOTDEMO/g" iframe-view/src/main/resources/view.xml    
sed -i "s#sandbox.hortonworks.com:6080#$HOSTNAME:$PORT/storm-demo-web-app#g" iframe-view/src/main/resources/index.html    
sed -i "s/iframe-view/iotdemo-view/g" iframe-view/pom.xml   
sed -i "s/Ambari iFrame View/IoTDemo View/g" iframe-view/pom.xml    
mv iframe-view iotdemo-view
cd iotdemo-view
echo "Starting mvn build. JAVA_HOME is $JAVA_HOME "
mvn clean package
echo "View compile complete"

echo "Setup complete"