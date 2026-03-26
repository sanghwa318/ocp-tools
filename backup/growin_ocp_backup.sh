#!/bin/bash

# GROWIN OpenShift Info Backup script
# create by oss@growin.co.kr (2025.02.03)

export DATE=`date +%Y%m%d`
export BACKUPDIR=/root/growin/${DATE}
mkdir -p ${BACKUPDIR}
#mkdir ${PATH}/statefulset ${PATH}/deployment ${PATH}/daemonset
export POD=${BACKUPDIR}/pod
export SVC=${BACKUPDIR}/service
export STS=${BACKUPDIR}/statefulset
export DEP=${BACKUPDIR}/deployment
export DEPC=${BACKUPDIR}/deploymentconfig
export DAE=${BACKUPDIR}/daemonset
export PV=${BACKUPDIR}/pv
export PVC=${BACKUPDIR}/pvc
export NODE=${BACKUPDIR}/node
export CO=${BACKUPDIR}/CO
export VM=${BACKUPDIR}/VM
export MC=${BACKUPDIR}/MC
export MCP=${BACKUPDIR}/MCP
export SC=${BACKUPDIR}/SC
export KC=${BACKUPDIR}/KC
export NAD=${BACKUPDIR}/NAD
export CSV=${BACKUPDIR}/CSV
export CM=${BACKUPDIR}/CM


mkdir -p $POD $SVC $STS $DEP $DEPC $DAE $PV $PVC $NODE $CO $VM $MC $MCP $SC $KC $NAD $CSV $CM

oc get node -o wide >> $BACKUPDIR/oc_get_node
oc get po -A -o wide >> $BACKUPDIR/oc_get_po_-A
oc get all -A -o wide >> $BACKUPDIR/oc_get_all_-A
oc get svc -A -o wide >> $BACKUPDIR/oc_get_svc_-A
oc get pvc -A -o wide >> $BACKUPDIR/oc_get_pvc_-A
oc get pv -A -o wide  >> $BACKUPDIR/oc_get_pv_-A
oc get ing -A -o wide >> $BACKUPDIR/oc_get_ing_-A
oc get sts -A -o wide >> $BACKUPDIR/oc_get_sts_-A
oc get route -A -o wide >> $BACKUPDIR/oc_get_route_-A
oc get deployment -A -o wide >> $BACKUPDIR/oc_get_deployment_-A
oc get daemonset -A -o wide >> $BACKUPDIR/oc_get_daemonset_-A
oc get deploymentconfigs -A -o wide >> $BACKUPDIR/oc_get_deploymentconfigs_-A
oc get mc -A -o wide >> $BACKUPDIR/oc_get_mc_-A
oc get mcp -A -o wide >> $BACKUPDIR/oc_get_mcp_-A
oc get co -A -o wide >> $BACKUPDIR/oc_get_co_-A
oc get vm -A -o wide >> $BACKUPDIR/oc_get_vm_-A
oc get sc -o wide >> $BACKUPDIR/oc_get_sc
oc get kubeletconfig -o wide >> $BACKUPDIR/oc_get_kc
oc get network-attachment-definition -A -o wide >> $BACKUPDIR/oc_get_nad_-A
oc api-resources >> $BACKUPDIR/oc_api-resources
oc get csv -A >> $BACKUPDIR/oc_get_csv_-A
oc get csv -A  | awk '{ print substr($0, index($0,$2)) }'|sort |uniq |grep -v PHASE >> $BACKUPDIR/oc_get_csv_-A_name_sort_uniq
oc get cm -A  >> $BACKUPDIR/oc_get_cm_-A


for i in $(oc get pod -A | grep -v NAME|awk '{print$1"_"$2}');
 do 
   NS=$(echo $i | awk  -F '_' '{print$1}'); 
   NAME=$(echo $i | awk -F '_' '{print$2}') ; 
   oc get pod -n ${NS} ${NAME} -o yaml > $POD/$i ;
done

 
for i in $(oc get svc -A | grep -v NAME|awk '{print$1"_"$2}');
 do 
   NS=$(echo $i | awk  -F '_' '{print$1}'); 
   NAME=$(echo $i | awk -F '_' '{print$2}') ; 
   oc get svc -n ${NS} ${NAME} -o yaml > $SVC/$i ;
done

for i in $(oc get sts -A | grep -v NAME|awk '{print$1"_"$2}');
 do 
   NS=$(echo $i | awk  -F '_' '{print$1}'); 
   NAME=$(echo $i | awk -F '_' '{print$2}') ; 
   oc get sts -n ${NS} ${NAME} -o yaml > $STS/$i ;
done

for i in $(oc get deployment -A | grep -v NAME|awk '{print$1"_"$2}');
 do
   NS=$(echo $i | awk  -F '_' '{print$1}');
   NAME=$(echo $i | awk -F '_' '{print$2}') ;
   oc get deployment -n ${NS} ${NAME} -o yaml > $DEP/$i ;
done

for i in $(oc get deploymentconfig -A | grep -v NAME|awk '{print$1"_"$2}');
 do 
   NS=$(echo $i | awk  -F '_' '{print$1}'); 
   NAME=$(echo $i | awk -F '_' '{print$2}') ; 
   oc get deploymentconfig -n ${NS} ${NAME} -o yaml > $DEPC/$i ;
done

for i in $(oc get daemonset -A | grep -v NAME|awk '{print$1"_"$2}');
 do
   NS=$(echo $i | awk  -F '_' '{print$1}');
   NAME=$(echo $i | awk -F '_' '{print$2}') ;
   oc get daemonset -n ${NS} ${NAME} -o yaml > $DAE/$i ;
done

for i in $(oc get node | grep -v NAME | awk '{print$1}');
do
  oc get node $i -o yaml > $NODE/$i;
done

for i in $(oc get co | grep -v NAME | awk '{print$1}');
do 
  oc get co $i -o yaml > $CO/$i;
done

for i in $(oc get pv |grep -v NAME | awk '{print$1}');
do
 oc get pv $i -o yaml > $PV/$i
done

for i in $(oc get pvc -A | grep -v NAME|awk '{print$1"_"$2}');
 do
   NS=$(echo $i | awk  -F '_' '{print$1}');
   NAME=$(echo $i | awk -F '_' '{print$2}') ;
   oc describe pvc -n ${NS} ${NAME} > $PVC/$i ;
done

for i in $(oc get mc  |grep -v NAME | awk '{print$1}');
 do
 oc get mc $i -o  yaml > $MC/$i
done
 
for i in $(oc get mcp  |grep -v NAME | awk '{print$1}');
 do
 oc get mcp $i -o yaml > $MCP/$i
done

for i in $(oc get vm -A | grep -v NAME | awk '{print$1"_"$2}');
do
NS=$(echo $i | awk  -F '_' '{print$1}');
NAME=$(echo $i | awk -F '_' '{print$2}') ;
    oc get vm -n ${NS} ${NAME} -o yaml > $VM/$i ;
done


for i in $(oc get sc  |grep -v NAME | awk '{print$1}');
 do
 oc get sc $i -o yaml > $SC/$i
done

for i in $(oc get kubeletconfig  |grep -v NAME | awk '{print$1}');
 do
 oc get kubeletconfig $i -o yaml > $KC/$i
done

for i in $(oc get network-attachment-definition -A | grep -v NAME | awk '{print$1"_"$2}');
do
NS=$(echo $i | awk  -F '_' '{print$1}');
NAME=$(echo $i | awk -F '_' '{print$2}') ;
    oc get network-attachment-definition -n ${NS} ${NAME} -o yaml > $NAD/$i ;
done


oc get csv -A >> $BACKUPDIR/oc_get_csv_-A
oc get csv -A  | awk '{ print substr($0, index($0,$2)) }'|sort |uniq |grep -v PHASE >> $BACKUPDIR/oc_get_csv_-A_sort_uniq
oc get cm -A  >> $BACKUPDIR/oc_get_cm_-A

for i in $(cat ${BACKUPDIR}/oc_get_csv_-A_sort_uniq |awk '{print$1}'); do grep $i $BACKUPDIR/oc_get_csv_-A | awk '{print"oc get csv -n "$1" "$2" -o yaml >> $CSV/"$1"_"$2".yaml"}' ;done|sh

for i in $(oc get cm -A | grep -v NAME | awk '{print$1"_"$2}');
do 
NS=$(echo $i | awk -F '_' '{print$1}');
NAME=$(echo $i | awk -F '_' '{print$2}') ;
oc get cm -n ${NS} ${NAME} -o yaml > $CM/$i;
done


####etcd backup


for i in $(oc get node -l node-role.kubernetes.io/master="" |awk '{print $1}' |grep -v NAME)
do
ssh core@$i "sudo -E /usr/local/bin/cluster-backup.sh /home/core/backup"
done
