
pragma solidity =0.4.26;
pragma experimental ABIEncoderV2;

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
interface TRC21 {
    function mint(address usr, uint wad) external;
    function burn(address usr, uint wad) external;
    function transferFrom(address src, address dst, uint wad) external returns (bool);
}
contract Voter {
    function vote() external payable;
    function unvote(uint _cap) external;
    function voterWithdrawDelay() external returns(uint);
    function withdraw(uint _blockNumber) external payable;
    function getWithdrawBlockNumbers() public view returns(uint256[]);
}
contract FiatContract {
    function getToken2USD(string __symbol) public view returns (string _symbolToken, uint _token2USD);
}
contract CDP_v1_2 is Ownable{
    using SafeMath for uint256;
    
    address public takeInterest = address(0x2076A228E6eB670fd1C604DE574d555476520DB7);
    address public Liquidatior = address(0x34C3A559cAFc7e2228e592a7E498c434249aED8b);
    Voter public CandidatesMasterNode = Voter(0x4690A3Beca75caa846709baf538c51eF97cF5408);
    FiatContract public Fiat = FiatContract(0x5410477d95454DE2796386F0aFDA58BBc45B5045);
    address public CDP_liquidated = address(0x0A7489E82C7d45FDFc29591bFf4319132BED2bC0);
    // ===== TFI bonus =======================
    bool public isBonusTFI;
    TRC21 public _tfi = TRC21(0x4A17A6605e3530B334940153D81AC9a637B542Cb);
    uint public TFIBonusPercent = 50;
    // ===== Campaign =======================
    bool public isCampaign;
    TRC21 public tokenCampaign = TRC21(0x4A17A6605e3530B334940153D81AC9a637B542Cb);
    uint public amountTokenCampaign = 1 ether;
    // ===== CDP =======================
    bool public systemBlock;
    uint public processMNPercent = 70;
    uint public interestRate = 10;

    uint public LiquidationRatio = 110;
    uint public LiquidationMinimum = 130;
    uint public minDeposit = 200 ether;
    uint public minPaybackPercent = 10;
    // ===== VAULT =======================
    mapping(address => uint[]) public userVaults;
    struct vaultBlock {
        uint nextBlock;
        uint TOMO;
        uint TAI;
        uint TOMOReqWD;
        uint TOMOReqWDFromOldVault;
    }
    struct vault {
        uint status; // 0: open; 1: liquidating; 2: liquidated
        uint currentBlock;
        mapping(uint => vaultBlock) vaultBlocks;
    }
    struct vaultList {
        mapping(uint => vault) vaults;
        uint currentVault;
        uint _block;
    }
    mapping(address => vaultList) public vaults;
    // =================================
    // ===== UNVOTE ====================
    
    struct unvote {
        uint block;
        uint amount;
        uint TOMOWD;
        uint status; // 1 waiting, 2 finish
    }
    mapping(address => unvote) public unvotes;
    struct unvotesBySystem {
        uint[] withdrawBlockNumbers;
        mapping(uint => unvote) unvotesBySystemPerVault;
    }
    mapping(address => unvotesBySystem) unvotesBySystems;
    // =================================
     modifier onlyLiquidatior() {
        require(msg.sender == Liquidatior);
        _;
    }

    constructor() public {}
    function() public payable {}
    event Execute(address _user, TRC21 _TAI, uint _TAIAmount, uint currentBlock);
    event Payback(address _user, TRC21 _TAI, TRC21 _TFI, uint _TAIAmount, uint _tfiAdmount, uint _interestAmount, uint _currentVault, uint _currentBlock);
    event ReqWd(address _user, uint _TAIAmount, uint _currentBlock, uint _unVoteIndex);
    event Withdraw(address _user, uint currentVault, uint _currentBlock, uint _type);
    event LiquidateVault(address _user, uint currentVault);
    event LiquidatedVault(address _user, uint withdrawBlockNumber);
    function toggleSystemBlock() public onlyOwner {
        systemBlock = !systemBlock;
    }
    function TOMO2TAI(uint _amount) public view returns (uint _TAI) {
        (, uint _token2USD) = Fiat.getToken2USD("TOMO");
        _TAI = _amount.mul(1 ether) / _token2USD;
        _TAI = _TAI * 100 / LiquidationMinimum;
    }
    function TOMORequirement(uint _amountTAI) public view returns (uint _TOMO) {
        (, uint _token2USD) = Fiat.getToken2USD("TOMO");
        _TOMO = _amountTAI * _token2USD / 1 ether;
        _TOMO += _TOMO * LiquidationRatio / 100;
    }
    function vote() internal {
        uint processAmount = msg.value.mul(processMNPercent) / 100;
        CandidatesMasterNode.vote.value(processAmount)();
    }
    function unVote(address user, uint _TOMO, uint _type) internal {
        uint processAmount = _TOMO.mul(processMNPercent) / 100;
        // CandidatesMasterNode.unvote(processAmount); // for test Liquidation
        uint256 withdrawBlockNumber = CandidatesMasterNode.voterWithdrawDelay().add(block.number);
        if(_type == 1) unvotes[user] = unvote(withdrawBlockNumber, processAmount, _TOMO, 1);
        else {
            unvotesBySystems[user].withdrawBlockNumbers.push(withdrawBlockNumber);
            unvotesBySystems[user].unvotesBySystemPerVault[withdrawBlockNumber] = unvote(withdrawBlockNumber, processAmount, _TOMO, 1);
        }
    }
    function getAvailableTomo(vaultBlock last, bool isCurrrentVault) public pure returns (uint _TOMO) {
        _TOMO = last.TOMO;
        if(isCurrrentVault) _TOMO -= last.TOMOReqWD;
    }
    function liquidateVault(address user) public onlyLiquidatior{
        uint currentVault = vaults[user].currentVault;
        require(vaults[user].vaults[currentVault].status == 0);
        
        uint currentBlock = vaults[user]._block;
        vaultBlock storage last = vaults[user].vaults[currentVault].vaultBlocks[currentBlock];
        uint liquidateTOMO = last.TOMO - last.TOMOReqWD;
        require( liquidateTOMO < TOMORequirement(last.TAI));
        
        uint256 withdrawBlockNumber = CandidatesMasterNode.voterWithdrawDelay().add(block.number);
        uint processAmount = liquidateTOMO.mul(processMNPercent) / 100;
        unvotesBySystems[user].withdrawBlockNumbers.push(withdrawBlockNumber);
        unvotesBySystems[user].unvotesBySystemPerVault[withdrawBlockNumber] = unvote(withdrawBlockNumber, processAmount, liquidateTOMO, 1);
        vaults[user].vaults[currentVault].status = 1;
        emit LiquidateVault(user, vaults[user].currentVault);
    }
    function liquidateVaults(address[] users) public onlyLiquidatior{
        require(users.length <= 200);
        for(uint i = 0; i < users.length; i++) {
            
            liquidateVault(users[i]);
        }
    }
    function _withdraw(address user, uint _type, uint _withdrawBlockNumber) internal {
        if(_type == 1) {
            // CandidatesMasterNode.withdraw(unvotes[user].block); // for test Liquidation
            unvotes[user].status = 2;   
        }
        else {
            require(unvotesBySystems[user].unvotesBySystemPerVault[_withdrawBlockNumber].status == 1);
            // CandidatesMasterNode.withdraw(_withdrawBlockNumber);  // for test Liquidation
            unvotesBySystems[user].unvotesBySystemPerVault[_withdrawBlockNumber].status = 2;   
            (bool _success) = CDP_liquidated.call.value(unvotesBySystems[user].unvotesBySystemPerVault[_withdrawBlockNumber].TOMOWD)(abi.encodeWithSignature("liquidated()"));
            require(_success);
        }
    }
    function withdraw(uint currentVault, uint _currentBlock) public payable{
        require(unvotes[msg.sender].status == 1);
        vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[_currentBlock];
        require(last.TOMOReqWD > 0);
        require(unvotes[msg.sender].block > 0);
        // require(block.number >= unvotes[msg.sender].block);  // for test Liquidation
       _withdraw(msg.sender, 1, 0);
        msg.sender.transfer(unvotes[msg.sender].TOMOWD);
        vaults[msg.sender].vaults[currentVault].vaultBlocks[_currentBlock].TOMO -= unvotes[msg.sender].TOMOWD;
        vaults[msg.sender].vaults[currentVault].vaultBlocks[_currentBlock].TOMOReqWD -= unvotes[msg.sender].TOMOWD;
        emit Withdraw(msg.sender, currentVault, _currentBlock, 1);
    }
    function liquidatedVault(address user, uint _index) public payable onlyOwner{
        
        _withdraw(user, 2, _index);
        emit LiquidatedVault(user, _index);
    }
     function liquidatedVaults(address[] users, uint[] _indexs) public payable onlyOwner{
         require(users.length <= 200);
        for(uint i = 0; i < users.length; i++) {
            liquidatedVault(users[i], _indexs[i]);
        }
    }
    function getUnvotesBySystems(address _user) public view returns(uint[] _withdrawBlockNumbers) {
        _withdrawBlockNumbers = unvotesBySystems[_user].withdrawBlockNumbers;
    }
    function getUnvotesBySystems(address _user, uint _index) public view returns( uint _block,
        uint _amount,
        uint _TOMOWD,
        uint _status) {
        return (unvotesBySystems[_user].unvotesBySystemPerVault[_index].block, 
        unvotesBySystems[_user].unvotesBySystemPerVault[_index].amount, 
        unvotesBySystems[_user].unvotesBySystemPerVault[_index].TOMOWD, 
        unvotesBySystems[_user].unvotesBySystemPerVault[_index].status);
    }
    function getUserVaults(address _user) public view returns (uint[] _userVaults){
        _userVaults = userVaults[_user];
    }
    function getVault(address _user, uint _vaultNo) public view returns (uint _status, uint _currentBlock){
        _status = vaults[_user].vaults[_vaultNo].status;
        _currentBlock = vaults[_user].vaults[_vaultNo].currentBlock;
    }
    function getVault(address _user, uint _vaultNo, uint _vaultBlock) public view returns (uint _nextBlock, uint _TOMO, uint _TAI, uint _TOMOReqWD, uint TOMOReqWDFromOldVault){
        _nextBlock = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].nextBlock;
        _TOMO = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TOMO;
        _TAI = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TAI;
        _TOMOReqWD = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TOMOReqWD;
        TOMOReqWDFromOldVault = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TOMOReqWDFromOldVault;
    }
    function updateVault(uint currentVault, uint _TOMO, uint _TAI, uint _TOMOReqWD, uint TOMOReqWDFromOldVault, uint _toBlock) internal{
        vaults[msg.sender].currentVault = currentVault;
        vaults[msg.sender]._block = _toBlock;

        vaults[msg.sender].vaults[0].currentBlock = _toBlock;
        vaults[msg.sender].vaults[currentVault].currentBlock = _toBlock;
        vaults[msg.sender].vaults[currentVault].vaultBlocks[_toBlock] = vaultBlock(_toBlock, _TOMO, _TAI, _TOMOReqWD, TOMOReqWDFromOldVault);
    }
    
    function updateVaultByDeposit(uint currentBlock, uint _TAIAmount) internal{

        if(vaults[msg.sender]._block == 0) {
            userVaults[msg.sender].push(0);
            updateVault(0, msg.value, _TAIAmount, 0, 0, block.number);
            if(isCampaign) {
                tokenCampaign.transferFrom(owner, msg.sender, amountTokenCampaign);
            }
        }
        else {
            uint currentVault = vaults[msg.sender].currentVault;
            vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock];
            if(vaults[msg.sender].vaults[currentVault].status == 0) {
                uint interestAmount = checkInteres(currentBlock, block.number, last.TAI);
                bonusTFI(interestAmount);
                updateVault(currentVault, last.TOMO + msg.value, last.TAI + _TAIAmount, last.TOMOReqWD, last.TOMOReqWDFromOldVault, block.number);
            } else updateVault(block.number, msg.value, _TAIAmount, last.TOMOReqWD, last.TOMOReqWDFromOldVault, block.number);
        }
    }

    function reqWd(uint currentVault, uint currentBlock, uint _TOMO) public {
        require(vaults[msg.sender].vaults[currentVault].status == 0);
        vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock];
        require(last.TOMO >= _TOMO);
        if(last.TOMO > _TOMO) require(last.TOMO - _TOMO >= minDeposit);
        
        unVote(msg.sender, _TOMO, 1);
        vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].TOMOReqWD = _TOMO;
        emit ReqWd(msg.sender, _TOMO, currentBlock, block.number);
    }
    function checkTFIearn(uint interestAmount) public view returns(uint _TFI) {
        _TFI = interestAmount.mul(TFIBonusPercent) / 100;
    }
    function bonusTFI(uint interestAmount) internal returns(uint _tfiAdmount) {
        _tfiAdmount = isBonusTFI ? checkTFIearn(interestAmount) : 0;
        if(_tfiAdmount > 0) _tfi.transferFrom(owner, msg.sender, _tfiAdmount);
    }
    function paybackSub(TRC21 _target, uint interestAmount, uint burnAmount) internal {
        require(_target.transferFrom(msg.sender, takeInterest, interestAmount));
        
        _target.burn(msg.sender, burnAmount);
    }
    
    function payback(TRC21 _target, uint currentVault, uint _toBlock, uint _TAIAmount, bool isPaybackAll) public {
        require(vaults[msg.sender].vaults[currentVault].status == 0);
        uint _fromBlock = vaults[msg.sender]._block;
        require(_toBlock > _fromBlock && _toBlock <= block.number);
        vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[_fromBlock];
        require(_TAIAmount <= last.TAI && _TAIAmount >= last.TAI * minPaybackPercent / 100);
        uint interestAmount;
        if(last.TAI > _TAIAmount) interestAmount = checkInteres(_fromBlock, _toBlock, last.TAI);
        else interestAmount = checkInteres(_fromBlock, block.number, last.TAI);
        require(_target.transferFrom(msg.sender, takeInterest, interestAmount));
        uint _tfiAdmount = bonusTFI(interestAmount);
        uint paybackAmount = isPaybackAll ? _TAIAmount : _TAIAmount.sub(interestAmount);
        paybackSub(_target, interestAmount, paybackAmount);
        updateVault(currentVault, last.TOMO, last.TAI - paybackAmount, last.TOMOReqWD, last.TOMOReqWDFromOldVault, _toBlock);
        emit Payback(msg.sender, _target, _tfi, paybackAmount, _tfiAdmount, interestAmount, currentVault, _fromBlock);
    }
    function checkInterestRatePerBlock(uint _TAIAmount) public view returns(uint interestRatePerBlock) {
        interestRatePerBlock = _TAIAmount.mul(interestRate) / 100 / 15768000;
    }
    function checkInteres(uint _fromBlock, uint _toBlock, uint _TAIAmount) public view returns(uint interest) {
        uint period = _toBlock.sub(_fromBlock);
        interest = checkInterestRatePerBlock(_TAIAmount).mul(period);
    }
    
    function execute(TRC21 _target, uint _TAIAmount) public payable {
        if(msg.value > 0) {
            require(msg.value >= minDeposit);
            // vote(); for test Liquidation
        }
        uint currentVault = vaults[msg.sender].currentVault;
        uint currentBlock = vaults[msg.sender]._block;
        vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock];
        
        uint availableTOMO = msg.value.add(last.TOMO);
        availableTOMO -= last.TOMOReqWD;
        uint TAIAmountMax = TOMO2TAI(availableTOMO);
        require(_TAIAmount <= TAIAmountMax);

        if(_TAIAmount > 0) _target.mint(msg.sender, _TAIAmount);
        updateVaultByDeposit(currentBlock, _TAIAmount);
        emit Execute(msg.sender, _target, _TAIAmount, currentBlock);
    }
    function config(uint _LiquidationRatio, uint _LiquidationMinimum, address _takeInterest, address _Liquidatior) public onlyOwner {
        LiquidationRatio = _LiquidationRatio;
        LiquidationMinimum = _LiquidationMinimum;
        takeInterest = _takeInterest;
        Liquidatior = _Liquidatior;
    }
    function setCampaign(TRC21 _tokenCampaign, bool _isCampaign, uint _amountTokenCampaign) public onlyOwner {
        tokenCampaign = _tokenCampaign;
        isCampaign = _isCampaign;
        amountTokenCampaign = _amountTokenCampaign;
    }
    function setTFIBonus(TRC21 __tfi, bool _isBonusTFI, uint _TFIBonusPercent) public onlyOwner {
        _tfi = __tfi;
        isBonusTFI = _isBonusTFI;
        TFIBonusPercent = _TFIBonusPercent;
    }
    function setVoter(address _CandidatesMasterNode) public onlyOwner {
        CandidatesMasterNode = Voter(_CandidatesMasterNode);
    }
    function setFIAT(FiatContract _fiat) public onlyOwner {
        Fiat = _fiat;
    }

    function refund(address _recipient) public {
        _recipient.transfer(address(this).balance);
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}