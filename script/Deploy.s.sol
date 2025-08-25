//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import{console} from "forge-std/console.sol";
import {DisputeMarket} from "../src/Dispute_Market.sol";

contract DeployDisputeMarket is Script {

    DisputeMarket disputeMarket;


    function run() external {

     uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
     address deployer = vm.addr(deployerPrivateKey);
        vm.createSelectFork(vm.rpcUrl("basechain"));
        vm.startBroadcast();
        vm.rpcUrl("localchain");
        deploy();
        setConfiguration(deployer);

        vm.stopBroadcast();
    }

 function deploy() public {
        disputeMarket = new DisputeMarket();
    }

   function setConfiguration(address _owners) public {
       disputeMarket.initialize(_owners);
    } 

 function getDeployedAddress() public view returns (address) {
        return address(disputeMarket);
    }



}