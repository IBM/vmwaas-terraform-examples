#!/bin/bash


# Check cURL command if available (required), abort if does not exists
type curl >/dev/null 2>&1 || { echo >&2 "This script requires jq, curl but it's not installed. Aborting."; exit 1; }

# Check jq command if available (required), abort if does not exists
type jq >/dev/null 2>&1 || { echo >&2 "This script requires jq, but it's not installed. Aborting."; exit 1; }

# Get args

case $1 in
    ins)
        echo "Get instances."
        echo
        
        action="INS"
        ;;

    in)
        echo "Get instance details."
        echo

        if [[ $2 == "" ]] 
        then
            echo "USAGE : vmwaas in '"'name-of-the-vdc'"'."
            exit 1
        else
            action="IN"
        fi

        ;;

    vdcs)
        echo "Get virtual datacenters."
        echo

        action="VDCS"
        ;;

    vdc)
        echo "Get details for a single virtual datacenter."
        echo

        if [[ $2 == "" ]] 
        then
            echo "USAGE : vmwaas vdc '"'name-of-the-vdc'"'."
            exit 1
        else
            action="VDC"
        fi

        ;;

    vdcgw)
        echo "Get details for a single virtual datacenter gateway and IP addresses."
        echo

        if [[ $2 == "" ]] 
        then
            echo "USAGE : vmwaas vdcgw '"'name-of-the-vdc'"'."
            exit 1
        else
            action="VDCGW"
        fi

        ;;

    tf)
        echo "Get variables for terraform for tfvars file."
        echo

        if [[ $2 == "" ]] 
        then
            echo "USAGE : vmwaas tf '"'name-of-the-vdc'"'."
            exit 1
        else
            action="TF"
        fi
        
        ;;

    tfvars)
        echo "Get variables for terraform in export format."
        echo

        if [[ $2 == "" ]] 
        then
            echo "USAGE : vmwaas tfvars '"'name-of-the-vdc'"'."
            exit 1
        else
            action="TF_VARS"
        fi

        ;;

    *)
       echo "USAGE : vmwaas [ ins | in | vdcs | vdc | vdcgw | tf | tfvars ]"
       echo
       echo
       
       exit
       ;;
esac



# Check API KEY environmental variable

if [[ $IBMCLOUD_API_KEY == "" ]] 
then
  echo "USAGE : vmwaas [ ins | in | vdcs | vdc | vdcgw | tf | tfvars ]"
  echo
  echo "ERROR: Set your API key with '"'export IBMCLOUD_API_KEY=your-api-key-here'"'"
  exit 1  
fi


# Check REGION environmental variable

if [[ $IBMCLOUD_REGION == "" ]] 
then
  REGION="us-south"
else
  REGION=$IBMCLOUD_REGION
fi


# Get IAM token

IAM_TOKEN=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" | jq -r .access_token)

URL="https://api.$REGION.vmware.cloud.ibm.com/v1"

if [[ $IAM_TOKEN == null ]] 
then
  echo
  echo "ERROR: Getting IAM token failed. Check your API key and REGION."
  echo
  echo "Set your API key with '"'export IBMCLOUD_API_KEY=your-api-key-here'"'"
  echo "Set your REGION with '"'export IBMCLOUD_REGION=region-here'"'. Default '"'us-south'"'"
  echo
  exit 1  
fi


####

if [ $action == "INS" ]
then

    ### Get instances


    ### Get instances

    INSTANCES=$(curl -s -X GET "$URL/director_sites" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo
    echo "Instances:"
    echo
    #echo $INSTANCES | jq -r .director_sites[]
    echo $INSTANCES  | jq -r ".director_sites[] | {name, id, location: .clusters[0].location, status}" | jq -n ".|= [inputs]" | jq -r '(["NAME","DIRECTOR_SITE_ID","LOCATION","STATUS"]), (.[] | [.name, .id, .location, .status]) | @tsv' | column -t


    echo

fi

####

if [ $action == "IN" ]
then


    ### Get instance

    INSTANCE_NAME=$2

    INSTANCES=$(curl -s -X GET "$URL/director_sites" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    INSTANCE_ID=$(echo $INSTANCES | jq '.director_sites[] | select( .name == "'$INSTANCE_NAME'" )' | jq -r .id)

    INSTANCE=$(curl -s -X GET "$URL/director_sites/$INSTANCE_ID" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo

    #echo "Instance details:"
    #echo $INSTANCE | jq .

    echo
    echo "Instance details:"
    echo
    echo $INSTANCE | jq ". | {name, id, location: .clusters[0].location, hosts: .clusters[0].host_count, profile: .clusters[0].host_profile}" | jq -n ".|= [inputs]" | jq -r '(["NAME","DIRECTOR_SITE_ID","LOCATION","HOSTS","PROFILE"]), (.[] | [.name, .id, .location, .hosts, .profile]) | @tsv' | column -t

    echo


    fi


####


if [ $action == "VDCS" ]
then

    ### Get VDCs


    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo
    echo "VDCs:"
    echo
    #echo $VDCS | jq ".vdcs[]"
    #echo $VDCS | jq ".vdcs[] | {name, id}" | jq -n ".|= [inputs]"
    #echo $VDCS | jq ".vdcs[] | {name, id}" | jq -n ".|= [inputs]" | jq -r '.[] | [.name, .id]'
    #echo $VDCS | jq ".vdcs[] | {name, id}" | jq -n ".|= [inputs]" | jq -r '.[] | [.name, .id] | @tsv ' | column -t
    echo $VDCS | jq ".vdcs[] | {name, id, crn, director_site: .director_site.id}" | jq -n ".|= [inputs]" | jq -r '(["NAME","ID","DIRECTOR_SITE_ID","CRN"]), (.[] | [.name, .id, .director_site, .crn]) | @tsv' | column -t

    echo


fi
####

if [ $action == "VDC" ]
then

    ### Get VDC

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo
    echo "VDC details:"
    echo
    #echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {name, org_name, url: .director_site.url}" 
    echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | [{name, org_name, url: .director_site.url}]" | jq -r '(["NAME","ORG","URL"]), (.[] | [.name, .org_name, .url]) | @tsv' | column -t

    echo

fi
####


if [ $action == "VDCGW" ]
then

    ### Get VDC GWs

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    echo
    echo "VDC Edge Gateways:"
    echo
    echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | [{type: .edges[0].type, id: .edges[0].id}]" | jq -r '(["TYPE","ID"]), (.[] | [.type, .id]) | @tsv' | column -t
    echo
    echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | [{public_ips: .edges[0].public_ips[]}]" | jq -r '(["PUBLIC_IP_ADDRESSES"]), (.[] | [.public_ips]) | @tsv' | column -t
    echo

fi
####


if [ $action == "TF" ]
then

    # Print TF_VARs

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    vmwaas_url=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {url: .director_site.url}" | jq -r .url | awk -F '/tenant.' '{print $1}')
    vmwaas_org=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {org_name"} | jq -r .org_name) 
    vmwaas_vdc_name=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {name"} | jq -r .name) 

    echo
    echo "tfvars lines:"
    echo  
    echo "vmwaas_url = "'"'$vmwaas_url"/api"'"'
    echo "vmwaas_org = "'"'$vmwaas_org'"'
    echo "vmwaas_vdc_name = "'"'$vmwaas_vdc_name'"' 
    echo


fi

####

if [ $action == "TF_VARS" ]
then

    # Print TF_VARs

    VDC_NAME=$2

    VDCS=$(curl -s -X GET "$URL/vdcs" -H "authorization: Bearer $IAM_TOKEN" -H "Content-Type:application/json")

    vmwaas_url=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {url: .director_site.url}" | jq -r .url | awk -F '/tenant.' '{print $1}')
    vmwaas_org=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {org_name"} | jq -r .org_name) 
    vmwaas_vdc_name=$(echo $VDCS | jq '.vdcs[] | select( .name == "'$VDC_NAME'" )' | jq ". | {name"} | jq -r .name) 

    echo
    echo "TF_VARs:"
    echo
    echo "export TF_VAR_vmwaas_url="'"'$vmwaas_url"/api"'"'
    echo "export TF_VAR_vmwaas_org="'"'$vmwaas_org'"'
    echo "export TF_VAR_vmwaas_vdc_name="'"'$vmwaas_vdc_name'"'
    echo

fi

####

