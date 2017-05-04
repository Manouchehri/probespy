#!/bin/bash

#TODO
#PRIORITY
#Query within N miles of Y coordinate
#Scriptargs
#Behavioral profile DB seed
#Behavioral profile info in report
#Plaintext report option

#BACK BURNER
#update report display format
#use sed to update report with new images
#use parallel where possible, script is far too linear
#optimize new SSID sorting per mac
#fix NULL display bug
#fix bug that prevent some SSIDs from being identified and cleared
#arg to designate directory where pcaps should be loaded from
#maybe force each run to create a new results directory


#set the internal field separator to newlines only
IFS=$'\n'

#Initialize variables
INTERFACE=''
WIGLE_API_KEY='AID0d903714c7d78b11a222c77b956d4200:78398fe46316092e08c3838355cad0e8'

#Defining script arguments
#work in progress
: 'while getopts "i:h" option;
do
        case $option in
        i)
                networkInterface=$OPTARG
                ;;
        h)
                echo "ProbeSpy anaylzes the contents of directed probe request to determine information about the device sending the requests.
        Dependencies:
        -tshark: Installed. Can be set to run as root, I dont care. Youll just have to sudo.
        -wget: For downloading some resources 
        Use:
        -i: The network interface [REQUIRED]
        -h: Display this help"
                exit
                ;;
        :)
                echo "option -$OPTARG needs an argument"
                exit
                ;;
        esac
done'

#INITIAL DATA PROCESSING
#clear old data
#rm -rf data/*

#clear pcaps from the ringbuffer directory
#rm ringbuffer/*

#TEMP DEV SHIT
#copy other pcaps in here because sometimes we dont have awesome sampling 
#cp ~/a/directory/*.cap ringbuffer/

#start capturing data from the wireless adapter to the ringbuffer
#tshark -i wlxc83a35c6c07a -f 'subtype probereq ' -w ringbuffer/probes -b duration:60 -b files:5 2> /dev/null &
#alternate with no ringbuffer
#tshark -i wlxc83a35c6c07a -f 'subtype probereq ' -w ringbuffer/probes 2> /dev/null &

#wait for tshark to write something to the ringbuffer dir before continuing
: '
echo -n "Initializing tshark"
while [ -z $(ls ringbuffer/) ]
do 
        echo -n .
        sleep 1
done
echo

#wait for a probe request before continuing
echo -n "Waiting for probe requests"
while [[ -z $probes ]]
do
        probes=$(for files in $( ls ringbuffer/);do sudo tshark -r ringbuffer/$files 2> /dev/null | grep "Probe Request, SN=";done)
	echo -n .
        sleep 1
done
echo


# perform the rest of these actions until the user cancels the script
while [ 1 -eq 1 ]
do
#'

#PCAP PROCESSING FUNCTION
pcap_processing () {

	#clear profile data from previous runs
	rm -rf data/*

	#do some actions for each capture file currently in the ringbuffer
	for i in $( ls ringbuffer/ );
	do
		#for each capture, output only the data we want
		#Source MAC and SSID
		for j in $( tshark -r ringbuffer/$i -Y 'wlan.fc.type_subtype == 0x0004' -Nn 2> /dev/null | grep -v 'SSID=Broadcast$' | cut -d '.' -f 2- | cut -d ' ' -f 2,12- | sed 's/ SSID=/,SSID=/g' | egrep -v "\\\001|\\\002|\\\003|\\\004|\\\005|\\\006|\\\016|\\\017|\\\020|\\\021|\\\022|\\\023|\\\024|\\\025|\\\026|\\\027|\\\030|\\\031|\\\032|\\\033|\\\034|\\\035|\\\036|\\\037|\\\277|\\\357" | sort -u ) 
		do
			echo $j >> data/$i.compressed
			#also create a file for each source mac from each capture file
			touch data/$(echo $j | cut -d , -f 1).mac
		done
	done

	#Create a sorted file of all compressed data
	cat data/*.compressed | sort -u > data/all.compressed
}

#GEOLOCATION
geolocation () {
	echo -------------------------------Begin SSID lookup---------------------------------

	#run a wigle query for all SSIDs listed in all.compressed
	#urlencode spaces with sed because curl bitches at you otherwise
	for i in $(cat data/all.compressed | cut -d = -f 2- | sort -u );
	do
		if [ -z "$(grep "\"ssid\"\:\"$i\"" location.db)" ]
		then
		        #entry is new
		        echo $i
		        #run query for the current SSID by wigle
		        #at this time, since we haven't determined better criteria, only 
		        #       keep entries that return one network            
		        wigle=`curl -s -u $WIGLE_API_KEY "https://api.wigle.net/api/v2/network/search?latrange1=&latrange2=&longrange1=&longrange2=&variance=0.010&lastupdt=&netid=&ssid=$(echo $i | sed 's/ /%20/g')&ssidlike=&Query=Query&resultsPerPage=2" | grep "\"resultCount\"\:1\," | cut -d \{ -f 3 | cut -d \} -f 1 | cut -d , -f 1-3,13 `
		        if [ -z "$wigle" ]
		        then
		                echo "\"trilat\":NULL,\"trilong\":NULL,\"ssid\":\"$i\",\"wep\":\"\"" >> location.db
		        else
		                echo -n $wigle >> location.db
				coordinates=$(echo $wigle | cut -d , -f 1-2 | sed -e 's/"trilat"://g' -e 's/"trilong"://g')
				address=$(curl -s https://maps.googleapis.com/maps/api/geocode/json?latlng=$coordinates | grep formatted_address | head -n1 | sed -e 's/.*:\ /,/g' -e 's/,$//g')
				echo $address >> location.db 
		        fi
			#sleep a little between queries because we don't want to be dicks
		        #DO WE?
			#Actually we don't care because we're paying for this shit
			#sleep 5
		fi
	done

	echo -----------------------------SSID lookup complete--------------------------------
}

#DEVICE PROFILING
# place SSID probes from each source MAC in it's own file 
# ensure that only uniq entries are in each file

profile_gen () {
	for i in $(cat data/all.compressed )
	do 
		echo $(echo $i | cut -d , -f 2) >> data/$(echo $i | cut -d , -f 1).mac
	done
}

#HTML GENERATION FUNCTION
html_gen () {
	#clear old html files
	rm html/*.html

	#generate a default display.html so there's always something 
	#for the active page to refresh to
	echo "<html><meta http-equiv="refresh" content="5"></head><body style="background-color\:black\;"><center><h1 style="color\:green\;font-family\:courier\;">BEAR WITH US<P>TECHNICAL DIFFICULTIES</h1><img src='../giphy.gif'><img src='../putin.jpeg'><img src='../giphy.gif'></center></html>" > html/display.html

	#perform these actions on each .mac profile
	for i in $( ls data/*.mac)
	do 
		#woo variables because we reuse them all the time
		mac=$(echo $i | cut -d \/ -f 2 | cut -d . -f 1)
		manufacturer=$(grep -i $(echo $mac | cut -d : -f -3 | sed 's/://g' ) /usr/share/ieee-data/oui.txt | cut -d '	' -f 3)

		#apply the following actions only on .mac profiles with more than one SSID
		if [ "$(cat $i | wc -l)" -gt 1 ]
		then 
			#Download google maps image for this location
			#for each SSID in this .mac profile
			for j in $(cat $i | cut -d = -f 2-)
			do 
				#create a variable for all this shit 
				#because we're going to be using it a LOT
				data=`grep ":\"$j\"," location.db | grep -v "\"trilat\":NULL,\"trilong\":NULL,"`
				ssid=`echo $data | cut -d , -f 3 | sed -e 's/\"ssid\":"//g' -e 's/\"$//g'`
				#display the current lat,lng
				latlng=`echo $data | cut -d , -f 1-2 | sed -e 's/"trilat"://g' -e 's/"trilong"://g'`
				#if the current SSID does not have google maps photo
				if ls html/$ssid.png 1> /dev/null 2>&1
				then
					#do nothing, file exists
					:
				else
					#if the file does not exst, see if we have
					#coordinates for it, don't download anything if we
					#don't. DUH
					if [[ $loc == *"\"trilat\":NULL,\"trilong\":NULL,"* ]]
					then
						:
					else
						wget -q https://maps.googleapis.com/maps/api/staticmap?markers=color:red%7Clabel:$ssid%7C$latlng\&zoom=13\&size=400x400\&maptype=roadmap -O html/$ssid.png
					fi
				fi
			done

	
			#generate html page	
			#for each SSID in this .mac profile
			for n in $(cat $i | cut -d = -f 2-)
			do
				if [ -z "$manufacturer" ]
				then
					manufacturer=$(echo UNKNOWN)
				fi


				#if an image exists for this network, add it to the html
				if [ -z $(ls html/*.png | grep "$n") ]
		                then
		                        :
		                else
					#if we haven't created an html file for this
					# profile yet, add the boilerplate header
					if [ -z "$(grep $mac html/*html)" ]
		                	then
						uniqueNets=$(cat $i | wc -l)
		                        	echo -n "<html><head><meta http-equiv=\"refresh\" content=\"15\"></head><style>table, th, td {border: 1px solid green;color: green;font-family: courier;border-collapse: collapse;} td { width:400px} body{background-color: black}h1 {color: green; text-align: left; font-family: courier; } p { color: green; font-family: courier; } h3 {color: green; font-family: courier; }</style><body><h1>Device ID $mac, manufacturer:$manufacturer is looking for $uniqueNets networks<h1> LOCATED_NETS_STRING_HERE nets have been located </h1><table><tr>" >> html/$mac.html
		                	fi
					#add the image to the profile
					address=$(grep $n location.db | cut -d , -f 5- | sed -e 's/^\"//g' -e 's/\"$//g'| sed 's/,/<h3>/')
					latlng=$(grep $n location.db | cut -d , -f 1-2 | sed -e 's/"trilat"://g' -e 's/"trilong"://g' )
					echo -n "<td><h3>$n<h3>$latlng<h3>$address<img src=\"$n.png\"></td>" >> html/$mac.html
					#echo -n "<tr><td rowspan=\"3\"><img src=\"$n.png\"</th><td>SSID: $n</td></tr><tr><td>COORDINATE: $latlng</td></tr><tr><td>ADDRESS: $address</td></tr>" >> html/$mac.html
		                fi
			done
		fi

		#now that the profile has been fully generated, replace placeholder for number of located networks with the actual value
		if [ -z "$(grep $mac html/*html)" ]
		then
			:
		else
			locatedNets=$(sed 's/\.png/.png\n/g' html/$mac.html  | wc -l)
			if [ $locatedNets -ne 0 ]
			then
				sed -i -e "s/LOCATED_NETS_STRING_HERE/$locatedNets/" html/$mac.html
			fi
		fi
	done
}

#remove all created profile .html files. Keep downloaded images so we're not wasteful
#for z in $(ls html/*.html)
#do
#	rm html/$(grep -v png $z | cut -d \> -f 4 | cut -d \< -f 1 | sed 's/$/.html/g')
#done

#CALL FUNCTIONS TO DO THINGS!
pcap_processing
geolocation
profile_gen
html_gen

#CHILL FUNCTION
chill_out () {
#just chill for a second. jesus
echo -n Chill out. Take a beat
for ani in $(seq 1 5)
do
	sleep 1
        echo -n .
done
echo " Back to it"
}

#chill_out

#continue looping
#done
