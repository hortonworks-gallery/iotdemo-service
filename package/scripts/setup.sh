#!/bin/bash
set -x 

export demo_root=$1
export STORMUI_HOSTNAME=$2
export PORT=$3
export JAVA_HOME=$4
export MVN_HOME=$5
export ambari_user=$6
export ambari_pass=$7

#AMBARI_HOST=`hostname -f`
#AMBARI_PORT=8080
#AMBARI_USER=admin
#AMBARI_PASS=admin
#AMBARI_CLUSTER=iotdemo
#MVN_HOME=/usr/local

echo "JAVA_HOME is $JAVA_HOME"
echo "MVN_HOME is $MVN_HOME"


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

python3 --version
ret=$? 

if [ ! $ret ]; then 
  echo "setup Python 3..."
  wget http://www.python.org/ftp/python/3.3.2/Python-3.3.2.tar.bz2 -O /var/tmp/Python-3.3.2.tar.bz2
  bzip2 -cd /var/tmp/Python-3.3.2.tar.bz2 | tar xvf -
  cd Python-3.3.2
  ./configure
  make
  sudo make install
  sudo ln -s /usr/local/bin/python3 /usr/bin/python3
  python3 --version
  rm -rf ${demo_root}/Python-3.3.2
else
  echo "Python 3 already installed"  
fi

cd ${demo_root}
if [ ! -f "$MVN_HOME/maven/bin/mvn" ]; then
  echo "Setup maven..."
  wget http://mirror.cc.columbia.edu/pub/software/apache/maven/maven-3/3.0.5/binaries/apache-maven-3.0.5-bin.tar.gz
  sudo tar xzf apache-maven-3.0.5-bin.tar.gz -C $MVN_HOME
  cd $MVN_HOME
  sudo ln -s apache-maven-3.0.5 maven
  export M2_HOME=$MVN_HOME/maven
  export PATH=${M2_HOME}/bin:${PATH}
  echo 'M2_HOME=/usr/local/maven' >> ~/.bashrc
  echo 'M2=$M2_HOME/bin' >> ~/.bashrc
  echo 'PATH=$PATH:$M2' >> ~/.bashrc
  rm -f apache-maven-3.0.5-bin.tar.gz
else
  echo "Maven already installed"  
fi

echo "Setup npm..."

sudo yum install -y epel-release                     ## needed on Centos 7
sudo yum install npm --enablerepo=epel -y
curl -0 -L http://npmjs.org/install.sh | sudo sh    ## needed on Centos 7
sudo npm install npm -g
sudo npm install grunt-cli -g 
sudo npm install bower -g


echo "Installing bower..."
cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-web-portal
bower install --allow-root

cd ${demo_root}
if [ ! -f /opt/activemq/latest/bin/activemq ]; then
  echo "Setup activemq..."
  sudo mkdir /opt/activemq
  cd /opt/activemq
  sudo wget http://archive.apache.org/dist/activemq/apache-activemq/5.9.0/apache-activemq-5.9.0-bin.tar.gz
  sudo tar xvzf apache-activemq-*.tar.gz
  sudo ln -s apache-activemq-5.9.0 latest
  rm -f apache-activemq-5.9.0-bin.tar.gz
else
  echo "Activemq already installed"   
fi

echo "Setup kafka..."
cd /usr/hdp/current/kafka-broker/bin
./kafka-topics.sh --create --zookeeper $(hostname -f):2181 --replication-factor 1 --partition 5 --topic truck_speed_events
./kafka-topics.sh --create --zookeeper $(hostname -f):2181 --replication-factor 1 --partition 5 --topic truck_events
./kafka-topics.sh --zookeeper $(hostname -f):2181 --list

echo "Setup HBase..."
echo "create 'driver_dangerous_events', {NAME=> 'events', VERSIONS=>3}" | hbase shell
echo "create 'driver_dangerous_events_count', {NAME=> 'counters', VERSIONS=>3}" | hbase shell
echo "create 'driver_events', {NAME=> 'allevents', VERSIONS=>3}" | hbase shell


set -e

echo "building hdp-app-utils..."
cd ${demo_root}/hdp/app-utils/hdp-app-utils 
$MVN_HOME/maven/bin/mvn clean install -DskipTests=true


echo "Building iot-trucking-app..."
cd ${demo_root}/hdp/reference-apps/iot-trucking-app 
$MVN_HOME/maven/bin/mvn clean install -DskipTests=true


echo "Building trucking-data-simulator assembly"
cd ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-data-simulator
$MVN_HOME/maven/bin/mvn assembly:assembly

set +e

#if installing demo on Ambari node, install latest storm view jar (if not already installed)
#if [ -d /var/lib/ambari-server/resources/views/ ] && [ ! -f /var/lib/ambari-server/resources/views/storm-view-0.1.0.0.jar ]; then
#  cd /var/lib/ambari-server/resources/views/
#  rm -f storm-view-2.*.jar
#  wget https://hipchat.hortonworks.com/files/1/1907/zF4FiDbf3sMXsjy/storm-view-0.1.0.0.jar
#  chmod 777 storm-view-0.1.0.0.jar
#fi


# if installing demo on Ambari node, deploy storm view
if [ -d /var/lib/ambari-server/ ]; then
  #Instantiate Storm view

  read -r -d '' body <<EOF
{
  "ViewInstanceInfo": {
    "instance_name": "StormAdmin", "label": "Storm View", "description": "Storm View",
    "visible": true,
    "properties": {
      "storm.host" : "${STORMUI_HOSTNAME}",
      "storm.port" : "8744"
    }
  }
}
EOF
  curl -ksSu ${ambari_user}:${ambari_pass} -H x-requested-by:blah http://localhost:8080/api/v1/views/Storm_Monitoring/versions/0.1.0/instances/StormAdmin -X DELETE
  echo "${body}" | curl -ksSu ${ambari_user}:${ambari_pass} -H x-requested-by:blah http://localhost:8080/api/v1/views/Storm_Monitoring/versions/0.1.0/instances/StormAdmin -X POST -d @-

fi


#if storm located on same node and its lib dir doesn't contain 2.6.2 log4j jars, replace 2.1 jars with 2.6
#if [ -d /usr/hd*/2.*/storm/lib/ ] && [ $(ls -la /usr/hd*/2.*/storm/lib/log4j*2.6.2.jar | wc -l) != 3 ]; then
#  echo "Updating storm jar in storm lib dir..."
#  mkdir ${demo_root}/oldjars
#  mv /usr/hd*/2.*/storm/lib/log4j*-2.1.jar ${demo_root}/oldjars
#  cp ${demo_root}/hdp/reference-apps/iot-trucking-app/trucking-data-simulator/target/log4j*-2.6.2.jar /usr/hd*/2.*/storm/lib/
#fi


echo "Setup complete"
