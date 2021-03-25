
pragma solidity =0.4.26;

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
contract CDP_v1_1 is Ownable{
    using SafeMath for uint256;
    
    address public takeInterest = address(0x2076A228E6eB670fd1C604DE574d555476520DB7);
    address public Liquidatior = address(0x34C3A559cAFc7e2228e592a7E498c434249aED8b);
    Voter public CandidatesMasterNode = Voter(0x7bcf8853AF0e0Bcf0d134702AA178dd7E8740995);
    FiatContract public Fiat = FiatContract(0x5410477d95454DE2796386F0aFDA58BBc45B5045);
    address public CDP_liquidated = address(0x5AFf39f630b5e9215A72Ba3C8b3F9E64281e5A29);
    // ===== TFI bonus =======================
    bool public isBonusTFI;
    TRC21 public _tfi = TRC21(0x5907AecF617c5019D9B3B43A5d65E583ce0F48BF);
    uint public TFIBonusPercent = 50;
    // ===== Campaign =======================
    bool public isCampaign;
    TRC21 public tokenCampaign = TRC21(0x5907AecF617c5019D9B3B43A5d65E583ce0F48BF);
    uint public amountTokenCampaign = 1 ether;
    // ===== CDP =======================
    uint mode = 1; // 1 vote less, 2 full
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
        uint unVoteIndex;
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
    // struct cdpUnvote{
    //     uint currentBlock;
    //     uint currentIndex;
    // }
    // mapping(uint => cdpUnvote) public cdpUnvotes;
    struct unvote {
        uint block;
        uint amount;
        uint TOMOWD;
        uint status; // 1 waiting, 2 finish
    }
    mapping(address => unvote) public unvotes;
    mapping(address => unvote) public unvotesBySystem;
    // =================================
     modifier onlyLiquidatior() {
        require(msg.sender == Liquidatior);
        _;
    }

    constructor() public {}
    event Execute(address _user, TRC21 _TAI, uint _TAIAmount, uint currentBlock);
    event Payback(address _user, TRC21 _TAI, TRC21 _TFI, uint _TAIAmount, uint _tfiAdmount, uint _interestAmount, uint _currentVault, uint _currentBlock);
    event ReqWd(address _user, uint _TAIAmount, uint _currentBlock, uint _unVoteIndex);
    event Withdraw(address _user, uint currentVault, uint _currentBlock, uint unVoteIndex);
    event LiquidateVault(address _user, uint currentVault);
    event LiquidatedVault(address _user, uint currentVault);
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
    function unVote(uint _TOMO, uint _type) internal {
        uint processAmount = _TOMO.mul(processMNPercent) / 100;
        CandidatesMasterNode.unvote(processAmount);
        uint256 withdrawBlockNumber = CandidatesMasterNode.voterWithdrawDelay().add(block.number);
        if(_type == 1) unvotes[msg.sender] = unvote(withdrawBlockNumber, processAmount, _TOMO, 1);
        else unvotesBySystem[msg.sender] = unvote(withdrawBlockNumber, processAmount, _TOMO, 1);
    }
    function _withdraw(address user, uint _type) internal {
        if(_type == 1) {
            CandidatesMasterNode.withdraw(unvotes[user].block);
            unvotes[user].status = 2;   
        }
        else {
            CandidatesMasterNode.withdraw(unvotesBySystem[user].block);
            unvotesBySystem[user].status = 2;   
        }
    }
    function withdraw(uint currentVault, uint _currentBlock) public payable{
        require(unvotes[msg.sender].status == 1);
        vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[_currentBlock];
        require(last.TOMOReqWD > 0);
        require(unvotes[msg.sender].block > 0);
        require(block.number >= unvotes[msg.sender].block);
       _withdraw(msg.sender, 1);
        msg.sender.transfer(unvotes[msg.sender].TOMOWD);
        emit Withdraw(msg.sender, currentVault, _currentBlock, last.unVoteIndex);
    }
    function liquidatedVault(address user) public payable onlyOwner{
        require(unvotesBySystem[user].status == 1);
        _withdraw(user, 2);
        (bool _success) = CDP_liquidated.call.value(unvotes[user].TOMOWD)(abi.encodeWithSignature("liquidated()"));
        require(_success);
        emit LiquidatedVault(user, vaults[user].currentVault);
    }
     function liquidatedVaults(address[] users) public payable onlyOwner{
         require(users.length <= 200);
        for(uint i = 0; i < users.length; i++) {
            liquidatedVault(users[i]);
        }
    }
    function getUserVaults(address _user) public view returns (uint[] _userVaults){
        _userVaults = userVaults[_user];
    }
    function getVault(address _user, uint _vaultNo) public view returns (uint _status, uint _currentBlock){
        _status = vaults[_user].vaults[_vaultNo].status;
        _currentBlock = vaults[_user].vaults[_vaultNo].currentBlock;
    }
    function getVault(address _user, uint _vaultNo, uint _vaultBlock) public view returns (uint _nextBlock, uint _TOMO, uint _TAI, uint _TOMOReqWD, uint _unVoteIndex){
        _nextBlock = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].nextBlock;
        _TOMO = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TOMO;
        _TAI = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TAI;
        _TOMOReqWD = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].TOMOReqWD;
        _unVoteIndex = vaults[_user].vaults[_vaultNo].vaultBlocks[_vaultBlock].unVoteIndex;
    }
    function updateVault(uint currentVault, uint _TOMO, uint _TAI, uint _TOMOReqWD, uint _unvoteIndex, uint _toBlock) internal{
        vaults[msg.sender].currentVault = currentVault;
        vaults[msg.sender]._block = _toBlock;

        vaults[msg.sender].vaults[0].currentBlock = _toBlock;
        vaults[msg.sender].vaults[currentVault].currentBlock = _toBlock;
        vaults[msg.sender].vaults[currentVault].vaultBlocks[_toBlock] = vaultBlock(_toBlock, _TOMO, _TAI, _TOMOReqWD, _unvoteIndex);
    }
    
    function liquidateVault(address user) public onlyLiquidatior{
        uint currentVault = vaults[user].currentVault;
        require(vaults[user].vaults[currentVault].status == 0);
        
        uint currentBlock = vaults[user]._block;
        vaultBlock storage last = vaults[user].vaults[currentVault].vaultBlocks[currentBlock];
        require(last.TOMO < TOMORequirement(last.TAI));
        unVote(last.TOMO, 2);
        vaults[user].vaults[currentVault].status = 1;
        vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].TOMOReqWD = last.TOMO;
        vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].unVoteIndex = block.number;
        emit LiquidateVault(user, vaults[user].currentVault);
    }
    function liquidateVaults(address[] users) public onlyLiquidatior{
        require(users.length <= 200);
        for(uint i = 0; i < users.length; i++) {
            
            liquidateVault(users[i]);
        }
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
                
                bonusTFI(currentBlock, block.number, last.TAI);
                updateVault(currentVault, last.TOMO + msg.value, last.TAI + _TAIAmount, last.TOMOReqWD, last.unVoteIndex, block.number);
            } else updateVault(block.number, msg.value, _TAIAmount, last.TOMOReqWD, last.unVoteIndex, block.number);
        }
    }

    function reqWd(uint currentVault, uint currentBlock, uint _TOMO) public {
        require(vaults[msg.sender].vaults[currentVault].status == 0);
        vaultBlock storage last = vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock];
        require(last.TOMO >= _TOMO);
        if(last.TOMO > _TOMO) require(last.TOMO - _TOMO >= minDeposit);
        
        unVote(_TOMO, 1);
        vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].TOMOReqWD = _TOMO;
        vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].unVoteIndex = block.number;
        emit ReqWd(msg.sender, _TOMO, currentBlock, block.number);
    }
    function bonusTFI(uint _fromBlock,uint _toBlock,uint _TAIAmount) internal returns(uint _tfiAdmount) {
        _tfiAdmount = isBonusTFI ? checkTFIearn(_fromBlock, _toBlock, _TAIAmount) : 0;
        if(_tfiAdmount > 0) _tfi.mint(msg.sender, _tfiAdmount);
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
        uint _tfiAdmount = bonusTFI(_fromBlock, _toBlock, last.TAI);
        uint paybackAmount = isPaybackAll ? _TAIAmount : _TAIAmount.sub(interestAmount);
        paybackSub(_target, interestAmount, paybackAmount);
        updateVault(currentVault, last.TOMO, last.TAI - paybackAmount, last.TOMOReqWD, last.unVoteIndex, _toBlock);
        emit Payback(msg.sender, _target, _tfi, paybackAmount, _tfiAdmount, interestAmount, currentVault, _fromBlock);
    }
    function checkInterestRatePerBlock(uint _TAIAmount) public view returns(uint interestRatePerBlock) {
        interestRatePerBlock = _TAIAmount.mul(interestRate) / 100 / 15768000;
    }
    function checkInteres(uint _fromBlock, uint _toBlock, uint _TAIAmount) public view returns(uint interest) {
        uint period = _toBlock.sub(_fromBlock);
        interest = checkInterestRatePerBlock(_TAIAmount).mul(period);
    }
    function checkTFIearn(uint _fromBlock, uint _toBlock, uint _TAIAmount) public view returns(uint _TFI) {
        _TFI = checkInteres(_fromBlock, _toBlock, _TAIAmount).mul(TFIBonusPercent) / 100;
    }
    function execute(TRC21 _target, uint _TAIAmount) public payable {
        if(msg.value > 0) {
            require(msg.value >= minDeposit);
            vote();
        }
        uint currentVault = vaults[msg.sender].currentVault;
        uint currentBlock = vaults[msg.sender]._block;
        uint availableTOMO = msg.value.add(vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].TOMO);
        availableTOMO -= vaults[msg.sender].vaults[currentVault].vaultBlocks[currentBlock].TOMOReqWD;
        uint TAIAmountMax = TOMO2TAI(availableTOMO);
        require(_TAIAmount <= TAIAmountMax);

        if(_TAIAmount > 0) _target.mint(msg.sender, _TAIAmount);
        updateVaultByDeposit(currentBlock, _TAIAmount);
        emit Execute(msg.sender, _target, _TAIAmount, currentBlock);
    }
    function config(uint _mode, uint _LiquidationRatio, uint _LiquidationMinimum, address _takeInterest, address _Liquidatior) public onlyOwner {
        mode = _mode;
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
}