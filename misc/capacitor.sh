#!/bin/bash

cap=400

if [ $1 -lt $cap ]; then



  address=$(lynx-cli getnewaddress) 



  for i in {$(seq $1 $cap)} 
  do 

    lynx-cli sendtoaddress $address 20

    sleep 1

  done



fi 


