#!/bin/bash

# Script is brought to you by ATADA_Stakepool, Telegram @atada_stakepool

#load variables from common.sh
#       socket          Path to the node.socket (also exports socket to CARDANO_NODE_SOCKET_PATH)
#       genesisfile     Path to the genesis.json
#       magicparam      TestnetMagic parameter
#       cardanocli      Path to the cardano-cli executable
#       cardanonode     Path to the cardano-node executable
. "$(dirname "$0")"/00_common.sh

case $# in
  3 ) fromAddr="$1";
      toAddr="$2";
      lovelacesToSend="$3";;
  * ) cat >&2 <<EOF
Usage:  $(basename $0) <From AddressName> <To AddressName or HASH> <Amount in lovelaces OR keyword ALL to send all lovelaces but keep your assets OR keyword ALLFUNDS to send all funds including Assets>
EOF
  exit 1;; esac

#Check if toAddr file doesn not exists, make a dummy one in the temp directory and fill in the given parameter as the hash address
if [ ! -f "$2.addr" ]; then echo "$2" > ${tempDir}/tempTo.addr; toAddr="${tempDir}/tempTo"; fi

if [ ! -f "${fromAddr}.addr" ]; then echo -e "\n\e[35mERROR - \"${fromAddr}.addr\" does not exist! Please create it first with script 03a or 02.\e[0m"; exit 1; fi
if [ ! -f "${fromAddr}.skey" ]; then echo -e "\n\e[35mERROR - \"${fromAddr}.skey\" does not exist! Please create it first with script 03a or 02.\e[0m"; exit 1; fi

echo -e "\e[0mSending lovelaces from Address\e[32m ${fromAddr}.addr\e[0m to Address\e[32m ${toAddr}.addr\e[0m:"
echo

#get live values
currentTip=$(get_currentTip)
ttl=$(get_currentTTL)
currentEPOCH=$(get_currentEpoch)

echo -e "\e[0mCurrent Slot-Height:\e[32m ${currentTip} \e[0m(setting TTL[invalid_hereafter] to ${ttl})"
echo

sendFromAddr=$(cat ${fromAddr}.addr)
sendToAddr=$(cat ${toAddr}.addr)

check_address "${sendFromAddr}"
check_address "${sendToAddr}"

echo -e "\e[0mSource Address ${fromAddr}.addr:\e[32m ${sendFromAddr} \e[90m"
echo -e "\e[0mDestination Address ${toAddr}.addr:\e[32m ${sendToAddr} \e[90m"
echo

#
# Checking UTXO Data of the source address and gathering data about total lovelaces and total assets
#
	utxoJSON=$(${cardanocli} ${subCommand} query utxo --address ${sendFromAddr} --cardano-mode ${magicparam} ${nodeEraParam} --out-file /dev/stdout); checkError "$?";
	txcnt=$(jq length <<< ${utxoJSON}) #Get number of UTXO entries (Hash#Idx), this is also the number of --tx-in for the transaction
	if [[ ${txcnt} == 0 ]]; then echo -e "\e[35mNo funds on the Source Address!\e[0m\n"; exit; else echo -e "\e[32m${txcnt} UTXOs\e[0m found on the Source Address!\n"; fi

        #Convert UTXO into mary style if UTXO is shelley/allegra style
        if [[ ! "$(jq -r '[.[]][0].amount | type' <<< ${utxoJSON})" == "array" ]]; then utxoJSON=$(convert_UTXO "${utxoJSON}"); fi

	#Calculating the total amount of lovelaces in all utxos on this address
        totalLovelaces=$(jq '[.[].amount[0]] | add' <<< ${utxoJSON})

        totalAssetsJSON="{}"; 	#Building a total JSON with the different assetstypes "policyIdHash.name", amount and name
        totalPolicyIDsJSON="{}"; #Holds the different PolicyIDs as values "policyIDHash", length is the amount of different policyIDs

	assetsOutString="";	#This will hold the String to append on the --tx-out if assets present or it will be empty

        #For each utxo entry, check the utxo#index and check if there are also any assets in that utxo#index
        #LEVEL 1 - different UTXOs
        for (( tmpCnt=0; tmpCnt<${txcnt}; tmpCnt++ ))
        do
        utxoHashIndex=$(jq -r "keys[${tmpCnt}]" <<< ${utxoJSON})
        utxoAmount=$(jq -r ".\"${utxoHashIndex}\".amount[0]" <<< ${utxoJSON})   #Lovelaces
        echo -e "Hash#Index: ${utxoHashIndex}\tAmount: ${utxoAmount}"
        assetsJSON=$(jq -r ".\"${utxoHashIndex}\".amount[1]" <<< ${utxoJSON})
        assetsEntryCnt=$(jq length <<< ${assetsJSON})
        if [[ ${assetsEntryCnt} -gt 0 ]]; then
                        #LEVEL 2 - different policyID/assetHASH
                        for (( tmpCnt2=0; tmpCnt2<${assetsEntryCnt}; tmpCnt2++ ))
                        do
                        assetHash=$(jq -r ".[${tmpCnt2}][0]" <<< ${assetsJSON})  #assetHash = policyID
                        assetsNameCnt=$(jq ".[${tmpCnt2}][1] | length" <<< ${assetsJSON})
                        totalPolicyIDsJSON=$( jq ". += {\"${assetHash}\": 1}" <<< ${totalPolicyIDsJSON})

                                #LEVEL 3 - different names under the same policyID
                                for (( tmpCnt3=0; tmpCnt3<${assetsNameCnt}; tmpCnt3++ ))
                                do
                                assetName=$(jq -r ".[${tmpCnt2}][1][${tmpCnt3}][0]" <<< ${assetsJSON})
                                assetAmount=$(jq -r ".[${tmpCnt2}][1][${tmpCnt3}][1]" <<< ${assetsJSON})
                                oldValue=$(jq -r ".\"${assetHash}.${assetName}\".amount" <<< ${totalAssetsJSON})
                                newValue=$((${oldValue}+${assetAmount}))
                                totalAssetsJSON=$( jq ". += {\"${assetHash}.${assetName}\":{amount: ${newValue}, name: \"${assetName}\"}}" <<< ${totalAssetsJSON})
                                echo -e "\e[90m            PolID: ${assetHash}\tAmount: ${assetAmount} ${assetName}\e[0m"
                                done
                         done
        fi
        txInString="${txInString} --tx-in ${utxoHashIndex}"
        done
        echo -e "\e[0m-----------------------------------------------------------------------------------------------------"
        totalInADA=$(bc <<< "scale=6; ${totalLovelaces} / 1000000")
        echo -e "Total ADA on the Address:\e[32m  ${totalInADA} ADA / ${totalLovelaces} lovelaces \e[0m\n"
        totalPolicyIDsCnt=$(jq length <<< ${totalPolicyIDsJSON});
        totalAssetsCnt=$(jq length <<< ${totalAssetsJSON})
        if [[ ${totalAssetsCnt} -gt 0 ]]; then
                        echo -e "\e[32m${totalAssetsCnt} Asset-Type(s) / ${totalPolicyIDsCnt} different PolicyIDs\e[0m found on the Address!\n"
                        printf "\e[0m%-70s %16s %s\n" "PolicyID.Name:" "Total-Amount:" "Name:"
                        for (( tmpCnt=0; tmpCnt<${totalAssetsCnt}; tmpCnt++ ))
                        do
                        assetHashName=$(jq -r "keys[${tmpCnt}]" <<< ${totalAssetsJSON})
                        assetAmount=$(jq -r ".\"${assetHashName}\".amount" <<< ${totalAssetsJSON})
                        assetName=$(jq -r ".\"${assetHashName}\".name" <<< ${totalAssetsJSON})
                        printf "\e[90m%-70s \e[32m%16s %s\e[0m\n" "${assetHashName}" "${assetAmount}" "${assetName}"
                        if [[ ${assetAmount} -gt 0 ]]; then assetsOutString+="+${assetAmount} ${assetHashName}"; fi #only include in the sendout if more than zero
                        done
        fi

echo

protocolParametersJSON=$(${cardanocli} ${subCommand} query protocol-parameters --cardano-mode ${magicparam} ${nodeEraParam})
checkError "$?"
minOutUTXO=$(get_minOutUTXO "${protocolParametersJSON}" "${totalAssetsCnt}" "${totalPolicyIDsCnt}")

#
# Depending on the input of lovelaces / keyword, set the right rxcnt (one receiver or two receivers)
#

case "${lovelacesToSend^^}" in

	"ALLFUNDS" )	#If keyword ALLFUNDS was used, send all lovelaces and all assets to the destination address
			rxcnt=1;;

	"ALL" )		#If keyword ALL was used, send all lovelaces to the destination address, but send back all the assets if available
			if [[ ${totalAssetsCnt} -gt 0 ]]; then
								rxcnt=2;	#assets on the address, they must be sent back to the source
							  else
								rxcnt=1;	#no assets on the address
							  fi;;

	* )		#If no keyword was used, its just the amount of lovelacesToSend
			rxcnt=2;;
esac


minUTXOvalue=$(jq -r .minUTxOValue <<< ${protocolParametersJSON})      #This value is the minimum value you have to send out in each --tx-out

#Generate Dummy-TxBody file for fee calculation
txBodyFile="${tempDir}/dummy.txbody"
rm ${txBodyFile} 2> /dev/null
if [[ ${rxcnt} == 1 ]]; then  #Sending ALLFUNDS or sending ALL lovelaces and no assets on the address
                        ${cardanocli} ${subCommand} transaction build-raw ${nodeEraParam} ${txInString} --tx-out "${dummyShelleyAddr}+0${assetsOutString}" --invalid-hereafter ${ttl} --fee 0 --out-file ${txBodyFile}
			checkError "$?"
                        else  #Sending chosen amount of lovelaces or ALL lovelaces but return the assets to the address
                        ${cardanocli} ${subCommand} transaction build-raw ${nodeEraParam} ${txInString} --tx-out "${dummyShelleyAddr}+0${assetsOutString}" --tx-out ${dummyShelleyAddr}+0 --invalid-hereafter ${ttl} --fee 0 --out-file ${txBodyFile}
			checkError "$?"
	fi
fee=$(${cardanocli} ${subCommand} transaction calculate-min-fee --tx-body-file ${txBodyFile} --protocol-params-file <(echo ${protocolParametersJSON}) --tx-in-count ${txcnt} --tx-out-count ${rxcnt} ${magicparam} --witness-count 1 --byron-witness-count 0 | awk '{ print $1 }')
checkError "$?"

echo -e "\e[0mMinimum Transaction Fee for ${txcnt}x TxIn & ${rxcnt}x TxOut: \e[32m ${fee} lovelaces \e[90m"
echo -e "\e[0mMinimum UTXO value for a Transaction: \e[32m ${minUTXOvalue} lovelaces \e[90m"
echo

#
# Depending on the input of lovelaces / keyword, set the right amount of lovelacesToSend, lovelacesToReturn and also check about sendinglimits like minUTxOValue for returning assets if available
#

case "${lovelacesToSend^^}" in

        "ALLFUNDS" )    #If keyword ALLFUNDS was used, send all lovelaces and all assets to the destination address - rxcnt=1
                        lovelacesToSend=$(( ${totalLovelaces} - ${fee} ))
			echo -e "\e[0mLovelaces to send to ${toAddr}.addr: \e[33m ${lovelacesToSend} lovelaces \e[90m"
			if [[ ${lovelacesToSend} -lt ${minOutUTXO} ]]; then echo -e "\e[35mNot enough funds on the source Addr! Minimum UTXO value is ${minOutUTXO} lovelaces.\e[0m"; exit; fi
			if [[ ${totalAssetsCnt} -gt 0 ]]; then	#assets are also send completly over, so display them
				echo -ne "\e[0m   Assets to send to ${toAddr}.addr: \e[33m "
				for (( tmpCnt=0; tmpCnt<${totalAssetsCnt}; tmpCnt++ ))
                        	do
                        	assetHashName=$(jq -r "keys[${tmpCnt}]" <<< ${totalAssetsJSON})
                        	assetAmount=$(jq -r ".\"${assetHashName}\".amount" <<< ${totalAssetsJSON})
                        	assetName=$(jq -r ".\"${assetHashName}\".name" <<< ${totalAssetsJSON})
                        	echo -ne "${assetAmount} ${assetName} / "
                        	done
				echo
			fi
			;;

        "ALL" )         #If keyword ALL was used, send all lovelaces to the destination address, but send back all the assets if available
                        if [[ ${totalAssetsCnt} -gt 0 ]]; then
                                                                #assets on the address, they must be sent back to the source address with the minUTXOvalue amount of lovelaces, rxcnt=2
								lovelacesToSend=$(( ${totalLovelaces} - ${fee} - ${minOutUTXO} )) #so send less over to
								lovelacesToReturn=${minOutUTXO} #minimum amount to return all the assets to the source address
                                                                echo -e "\e[0mLovelaces to send to ${toAddr}.addr: \e[33m ${lovelacesToSend} lovelaces \e[90m"
                                                                echo -e "\e[0mLovelaces to return to ${fromAddr}.addr: \e[32m ${lovelacesToReturn} lovelaces \e[90m (this is needed to prevent all the assets on the source address)"
                                                                if [[ ${lovelacesToSend} -lt ${minUTXOvalue} ]]; then echo -e "\e[35mNot enough funds on the source Addr! Minimum UTXO value is ${minUTXOvalue} lovelaces.\e[0m"; exit; fi
                                                          else
                                                                #no assets on the address, so just send over all the lovelaces, rxcnt=1
                        					lovelacesToSend=$(( ${totalLovelaces} - ${fee} ))
                        					echo -e "\e[0mLovelaces to send to ${toAddr}.addr: \e[33m ${lovelacesToSend} lovelaces \e[90m"
								if [[ ${lovelacesToSend} -lt ${minUTXOvalue} ]]; then echo -e "\e[35mNot enough funds on the source Addr! Minimum UTXO value is ${minUTXOvalue} lovelaces.\e[0m"; exit; fi
                                                          fi;;

        * )             #If no keyword was used, its just the amount of lovelacesToSend to the destination address, rest will be returned to the source address, rxcnt=2
                        echo -e "\e[0mLovelaces to send to ${toAddr}.addr: \e[33m ${lovelacesToSend} lovelaces \e[90m"
                        if [[ ${lovelacesToSend} -lt ${minUTXOvalue} ]]; then echo -e "\e[35mNot enough lovelaces to send to the destination! Minimum UTXO value is ${minUTXOvalue} lovelaces.\e[0m"; exit; fi
			lovelacesToReturn=$(( ${totalLovelaces} - ${fee} - ${lovelacesToSend} ))
                        echo -e "\e[0mLovelaces to return to ${fromAddr}.addr: \e[32m ${lovelacesToReturn} lovelaces \e[90m"
                        if [[ ${lovelacesToReturn} -lt ${minOutUTXO} ]]; then echo -e "\e[35mNot enough funds on the source Addr to return the rest! Minimum UTXO value is ${minUTXOvalue} lovelaces.\e[0m";
										if [[ ${lovelacesToSend} -ge ${totalLovelaces} ]]; then echo -e "\e[35mIf you wanna send out ALL your lovelaces, use the keyword ALL instead of the amount.\e[0m";fi
										exit; fi
			;;
esac

txBodyFile="${tempDir}/$(basename ${fromAddr}).txbody"
txFile="${tempDir}/$(basename ${fromAddr}).tx"

echo
echo -e "\e[0mBuilding the unsigned transaction body: \e[32m ${txBodyFile} \e[90m"
echo

#Building unsigned transaction body
rm ${txBodyFile} 2> /dev/null
if [[ ${rxcnt} == 1 ]]; then  #Sending ALL funds  (rxcnt=1)
			${cardanocli} ${subCommand} transaction build-raw ${nodeEraParam} ${txInString} --tx-out "${sendToAddr}+${lovelacesToSend}${assetsOutString}" --invalid-hereafter ${ttl} --fee ${fee} --out-file ${txBodyFile}
			checkError "$?"
			else  #Sending chosen amount (rxcnt=2), return the rest(incl. assets)
			${cardanocli} ${subCommand} transaction build-raw ${nodeEraParam} ${txInString} --tx-out ${sendToAddr}+${lovelacesToSend} --tx-out "${sendFromAddr}+${lovelacesToReturn}${assetsOutString}" --invalid-hereafter ${ttl} --fee ${fee} --out-file ${txBodyFile}
			#echo -e "\n\n\n${cardanocli} ${subCommand} transaction build-raw ${nodeEraParam} ${txInString} --tx-out ${sendToAddr}+${lovelacesToSend} --tx-out \"${sendFromAddr}+${lovelacesToReturn}${assetsOutString}\" --invalid-hereafter ${ttl} --fee ${fee} --out-file ${txBodyFile}\n\n\n"
			checkError "$?"
fi

cat ${txBodyFile}
echo

echo -e "\e[0mSign the unsigned transaction body with the \e[32m${fromAddr}.skey\e[0m: \e[32m ${txFile} \e[90m"
echo

#Sign the unsigned transaction body with the SecureKey
rm ${txFile} 2> /dev/null
${cardanocli} ${subCommand} transaction sign --tx-body-file ${txBodyFile} --signing-key-file ${fromAddr}.skey ${magicparam} --out-file ${txFile} 
checkError "$?"

cat ${txFile}
echo

if ask "\e[33mDoes this look good for you, continue ?" N; then
	echo
	echo -ne "\e[0mSubmitting the transaction via the node..."
	${cardanocli} ${subCommand} transaction submit --tx-file ${txFile} --cardano-mode ${magicparam}
	checkError "$?"
	echo -e "\e[32mDONE\n"
fi

echo -e "\e[0m\n"



