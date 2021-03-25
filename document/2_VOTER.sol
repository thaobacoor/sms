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
    function unvote(address _candidate, uint _cap) external;
    function voterWithdrawDelay() external returns(uint);
    function withdraw(uint256 _blockNumber, uint _index) external;
    function getWithdrawCap(uint _blockNumber) public view returns(uint256);
    function getWithdrawBlockNumbers() public view returns(uint256[]);
}
contract Voter_1 is Ownable {
    using SafeMath for uint256;
    MasterNode public CandidatesMasterNode = MasterNode(0x0000000000000000000000000000000000000088);
    address constant public validator = 0x0000000000000000000000000000000000000088;

    // (v, r, s) sign of root
    uint8 private v = 0x1b;
    bytes32 private r = 0x56cca24e4ebe9b4350d35bcb09c240cd983851fa56a2c5fa5b5d311dba8236eb;
    bytes32 private s = 0x3d3da2f752fd981fb78b184df3d7057da0be6fce3a7a923b478365d95a32f013;
    address public candidate = address(0x8A97753311aeAFACfd76a68Cf2e2a9808d3e65E8);
    address public voter;
    address public ceo;
    address public address30;
    address public address70;
    bool public lockSystem;
    uint public requestWDRWBlock;
    uint public requestChangeConfigBlock;
    uint256 constant public BLOCK_PER_REQ = 900;
    uint256 public withdrawIndex = 1;
    //this is used for storing the state and history of unvotes
    struct WithdrawState {
        bool isWithdrawnStakeLocked;
        bool isWithdrawnCandidateLocked;
        mapping(uint256 => uint256) caps;
        uint256[] blockNumbers;
    }
    //map from block number to index
    mapping(uint256 => uint256) public indexes;//this corresponds the index parameter in tomovalidator withdraw function
    //history of unvote is saved per epoch
    mapping(address => WithdrawState) withdrawsState;
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
    modifier onlyRoot(string _secret) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(_secret))));
        address root = ecrecover(digest, v, r, s);
        require(msg.sender == root);
        _;
    }
    constructor() public {
        ceo = msg.sender;
        address30 = msg.sender;
        address70 = msg.sender;
        voter = 0x2076A228E6eB670fd1C604DE574d555476520DB7;
    }
    function() public payable { }
    function voterWithdrawDelay() public view returns(uint) {
        return CandidatesMasterNode.voterWithdrawDelay();
    }
    function getWithdrawBlockNumbers() public view returns(uint256[]) {
        return CandidatesMasterNode.getWithdrawBlockNumbers();
    }
    // function withdraw(uint256 _blockNumber) public onlyVoter {
    function withdraw(uint256 _blockNumber) public{
        require(indexes[_blockNumber] > 0);
        uint WithdrawCap = CandidatesMasterNode.getWithdrawCap(_blockNumber);
        (bool success) = validator.call(abi.encodeWithSignature("withdraw(uint256,uint256)", _blockNumber, indexes[_blockNumber].sub(1)));
        require(success);
        // CandidatesMasterNode.withdraw(_blockNumber, indexes[_blockNumber].sub(1));
        delete indexes[_blockNumber];
        msg.sender.transfer(WithdrawCap);
    }
    function unvote(uint _TOMO) public onlyVoter {
        //save withdrawsState
        // refund after delay X blocks
        uint256 withdrawBlockNumber = CandidatesMasterNode.voterWithdrawDelay().add(block.number);
        //only one stake can be done in a block to avoid withdraw collision
        require(indexes[withdrawBlockNumber] == 0, "another voter already unvote in this block");
        withdrawsState[msg.sender].blockNumbers.push(withdrawBlockNumber);
        indexes[withdrawBlockNumber] = withdrawIndex;
        withdrawIndex = withdrawIndex.add(1);
        (bool success) = validator.call(abi.encodeWithSignature("unvote(address,uint256)", candidate, _TOMO));
            require(success, "unvote failed");
        // CandidatesMasterNode.unvote(candidate, _TOMO);
    }
    function vote() public payable onlyVoter {
        // CandidatesMasterNode.vote.value(msg.value)(candidate);
        (bool success) = validator.call.value(msg.value)(abi.encodeWithSignature("vote(address)", candidate));
            require(success, "Vote fail");
    }
    function setVoter(address _voter) public onlyOwner {
        voter = _voter;
    }
    function setLock() public onlyCeo {
        lockSystem = true;
    }
    
    function setUnlock(string _secret) public onlyRoot(_secret) {
        lockSystem = false;
    }
    function changeCeo(address _ceo, string _secret) public onlyRoot(_secret) {
        ceo = _ceo;
    }
    function requestChangeConfig() public onlyCeo {
        require(requestChangeConfigBlock == 0);
        requestChangeConfigBlock = block.number;
        emit RequestChangeConfig(msg.sender, block.timestamp);
    }
    function config(address _address30, address _address70) public onlyCeo {
        require(!lockSystem);
        require(requestChangeConfigBlock > 0 && block.number - requestChangeConfigBlock > BLOCK_PER_REQ);
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
        require(requestWDRWBlock > 0 && block.number - requestWDRWBlock > BLOCK_PER_REQ);
        requestWDRWBlock = 0;
        address30.transfer(address(this).balance.mul(3).div(10));
        address70.transfer(address(this).balance.mul(7).div(10));
        emit WithdrawReward(address30, address70, address(this).balance);
    }
}