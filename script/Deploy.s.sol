//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import{console} from "forge-std/console.sol";
import {DisputeMarket} from "../src/Dispute_Market.sol";
import{PariMutuelBetting } from "../src/BettingPool.sol";

contract DeployDisputeMarket is Script {

    DisputeMarket disputeMarket;
    PariMutuelBetting  betting;


    function run() external {
	uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
	address deployer = vm.addr(deployerPrivateKey);
	address kwn = vm.envAddress("KWN");
	address treasury = vm.envAddress("TREASURY");
	uint256 tieSlash = vm.envOr("TIE_SLASH_BPS", uint256(400)); // default 4%

        vm.createSelectFork(vm.rpcUrl("kaiatestnet"));
        vm.startBroadcast(deployerPrivateKey);
        deploy(kwn, treasury, uint16(tieSlash));
        setConfiguration(deployer);
        getDeployedAddress();
        vm.stopBroadcast();
      
    }

 function deploy(address _kwn, address _treasury, uint16 _tieSlashBps) public {
    console.log("Deploying DisputeMarket...");
        disputeMarket = new DisputeMarket();
        console.log("Deploying PariMutuelBetting...");
        betting = new PariMutuelBetting(_kwn,  address(disputeMarket), _treasury);
        if (_tieSlashBps > 0) {
            betting.setTieSlashBps(_tieSlashBps);
        }
    }

   function setConfiguration(address _owners) public {
    console.log("initializing DisputeMarket with owner:", _owners);
       disputeMarket.initialize(_owners);
    } 

 function getDeployedAddress() public view returns (address) {
    console.log("DisputeMarket Deployed at:", address(disputeMarket));
    console.log("PariMutuelBetting Deployed at:", address(betting));
        return address(disputeMarket);
        
    }



}