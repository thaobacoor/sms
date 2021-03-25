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

contract CDP_liquidated is Ownable {
    using SafeMath for uint256;
    address ceo = 0x2076A228E6eB670fd1C604DE574d555476520DB7;
    address TAI = 0x30d78B484f0049fD8775c9CB21F562aDf18B593a;
    uint Fee_balance_system = 10; // percent
    modifier onlyCeo() {
        require(msg.sender == ceo);
        _;
    }
    constructor() public {}
    function() public payable {}
    function _burn(uint _wad) public onlyCeo {
        (bool _success) = TAI.call(abi.encodeWithSignature("burn(address usr, uint wad)", address(this), _wad));
        require(_success);
    }
    function burn(uint _wad) public onlyCeo {
        (bool success) = TAI.call(abi.encodeWithSignature("transferFrom(address src, address dst, uint wad)", msg.sender, address(this), _wad));
        require(success);
        _burn(_wad.mul(100).div(100 + Fee_balance_system));
    }
    function liquidated() public payable {
        require(msg.value > 0);
        ceo.transfer(msg.value);
    }
    
}