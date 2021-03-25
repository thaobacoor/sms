// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.4.26;

contract Ownable {
    address public owner;


    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

}



/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }
}
contract MasterNode {
    function vote(address _candidate) external payable;
    function unvote(address _candidate, uint256 _cap) external;
    function voterWithdrawDelay() external returns(uint);
    function withdraw(uint256 _blockNumber, uint _index) external;
}

contract Voter is Ownable {
    using SafeMath for uint256;
    MasterNode public CandidatesMasterNode = MasterNode(0x0000000000000000000000000000000000000088);
    // (v, r, s) là chữ ký của root
    uint8 private v = 0;
    bytes32 private r = 0x08c379a000000000000000000000000000000000000000000000000000000000;
    bytes32 private s = 0x0000002000000000000000000000000000000000000000000000000000000000;
    address public ceo;
    address public voter;
    address public address30;
    address public address70;
    bool public lockSystem;
    uint public requestWDRWBlock;
    uint public requestChangeConfigBlock;
    event WithdrawReward(address _address, address _sTFI, uint _TOMO);
    event RequestChangeConfig(address _address, uint _timestamp);
    event Config(address _address, address _sTFI);
    event RequestWithdrawReward(address _address, uint _timestamp);
    modifier onlyVoter() {
        require(msg.sender == voter);
        _;
    }
    modifier onlyCeo() {
        require(msg.sender == ceo);
        _;
    }
    modifier onlyRoot(_secret) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(_secret))));
        address root = ecrecover(digest, v, r, s);
        require(msg.sender == root);
        _;
    }
    constructor() public {
        ceo = msg.sender;
        voter = msg.sender;
        address30 = msg.sender;
        address70 = msg.sender;
    }
        
    function withdraw(uint256 _blockNumber, uint _index) public onlyVoter {
        CandidatesMasterNode.withdraw(_blockNumber, _index);
    }
    function unVote(address _candidate, uint _TOMO) public onlyVoter {
        CandidatesMasterNode.unvote(_candidate, _TOMO);
    }
    function vote(address _candidate) public payable onlyVoter {
        CandidatesMasterNode.vote.value(msg.value)(_candidate);
    }
    function setVoter(address _voter) public onlyOwner {
        voter = _voter;
    }
    function setLock() public onlyCeo {
        lockSystem = true;
    }
    function setUnlock() public onlyRoot(_secret) {
        lockSystem = false;
    }
     function changeCeo(address _ceo) public onlyRoot(_secret) {
        ceo = _ceo;
    }
    function requestChangeConfig() public onlyCeo {
        require(requestChangeConfigBlock == 0);
        requestChangeConfigBlock = block.number;
        emit RequestChangeConfig(msg.sender, block.timestamp);
    }
    function config(address _address30, address _address70) public onlyCeo {
        require(!lockSystem);
        require(requestChangeConfigBlock > 0 && block.number - requestChangeConfigBlock > 9);
        requestChangeConfigBlock = 0;
        address30 = _address30;
        address70 = _address70; 
        emit Config(_address30, _address70);
    }
    function requestWithdrawReward() public onlyCeo {
        require(requestWDRWBlock == 0);
        requestWDRWBlock = block.number;
        emit RequestWithdrawReward(msg.sender, block.timestamp);
    }
    function withdrawReward() public onlyCeo {
        require(!lockSystem);
        require(requestWDRWBlock > 0 && block.number - requestWDRWBlock > 9);
        requestWDRWBlock = 0;
        address30.transfer(address(this).balance.mul(3).div(10));
        address70.transfer(address(this).balance.mul(7).div(10));
        emit WithdrawReward(address30, address70, address(this).balance);
    }
}