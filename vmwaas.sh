#!/bin/bash


# Check cURL command if available (required), abort if does not exists
type curl >/dev/null 2>&1 || { echo >&2 "This script requires jq, curl but it's not installed. Aborting."; exit 1; }
echo

# Check jq command if available (required), abort if does not exists
type jq >/dev/null 2>&1 || { echo >&2 "This script requires jq, but it's not installed. Aborting."; exit 1; }
echo


# Get IAM token

REGION="us-south"

IAM_TOKEN=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" | jq -r .access_token)

URL="https://api.$REGION.vmware.cloud.ibm.com/v1"


# Get args

case $1 in
    ins)
        echo "Get instances."
        echo
        
        action="INS"
        ;;

    in)
        echo "Get instances."
        echo
        
        action="IN"
        ;;

    vdcs)
        echo "Get virtual datacenters."
        echo
        
        action="VDCS"
        ;;

    vdc)
        echo "Get details for a single virtual datacenter."
        echo "USAGE : vmwaas wdc '"'name-of-the-vdc'"'."
        echo

        action="VDC"
        ;;

    tf)
        echo "Get variables for terraform for tfvars file."
        echo "USAGE : vmwaas tf '"'name-of-the-vdc'"'."
        echo

        action="TF"
        ;;

    tfvars)
        echo "Get variables for terraform in export format."
        echo "USAGE : vmwaas tfvars '"'name-of-the-vdc'"'."
        echo
        
        action="TF_VARS"
        ;;

    *)
       echo "USAGE : vmwaas [ ins | in | vdcs | vdc | tf | tfvars ]"
       echo
       
       exit
       ;;
esac


####

if [ $action == "INS" ]
then

    ### Get instances


    ### Get instances

    INSTANCES=$(curl -s -X GET "$URL/director_sites" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo "Instances:"
    echo $(echo $INSTANCES | jq -r .director_sites[].name)


    echo

fi

####

if [ $action == "IN" ]
then


    ### Get instance

    INSTANCE_NAME=$2

    INSTANCES=$(curl -s -X GET "$URL/director_sites" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    INSTANCE_ID=$(echo $INSTANCES | jq '.director_sites[0] | select( .name == "'$INSTANCE_NAME'" )' | jq -r .id)

    echo "Instance ID filtered:"
    echo $INSTANCE_ID

    INSTANCE=$(curl -s -X GET "$URL/director_sites/$INSTANCE_ID" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo

    #echo "Instance details:"
    #echo $INSTANCE | jq .

    echo "Instance details filtered:"
    echo $INSTANCE | jq ". | {name, id, clusters: .clusters}" 


    echo


    fi


####


if [ $action == "VDCS" ]
then

    ### Get VDCs


    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo "VDCs:"
    echo $VDCS | jq ".vdcs[] | {name, id}" | jq -n ".|= [inputs]"

    echo


fi
####

if [ $action == "VDC" ]
then

    ### Get VDC

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    #echo "VDC details:"
    #echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' 

    echo "VDC details filtered:"
    echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {name, org_name, url: .director_site.url}"

fi
####


if [ $action == "TF" ]
then

    # Print TF_VARs

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo "tfvars lines:"

    vmwaas_url=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {url: .director_site.url}" | jq -r .url | awk -F '/tenant.' '{print $1}')
    vmwaas_org=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {org_name"} | jq -r .org_name) 
    vmwaas_vdc_name=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {name"} | jq -r .name) 

    echo "vmwaas_url = "'"'$vmwaas_url"/api"'"'
    echo "vmwaas_org = "'"'$vmwaas_org'"'
    echo "vmwaas_vdc_name = "'"'$vmwaas_vdc_name'"'


fi

####

if [ $action == "TF_VARS" ]
then

    # Print TF_VARs

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo "TF_VARs:"

    vmwaas_url=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {url: .director_site.url}" | jq -r .url | awk -F '/tenant.' '{print $1}')
    vmwaas_org=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {org_name"} | jq -r .org_name) 
    vmwaas_vdc_name=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {name"} | jq -r .name) 

    echo "export TF_VAR_vmwaas_url="'"'$vmwaas_url"/api"'"'
    echo "export TF_VAR_vmwaas_org="'"'$vmwaas_org'"'
    echo "export TF_VAR_vmwaas_vdc_name="'"'$vmwaas_vdc_name'"'


fi

####

