// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";         
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./Interfaces/INFT.sol";
import "./Relayer/BasicMetaTransaction.sol";
import "./UniSwapContracts/interfaces/IUniswapV2Router02.sol";
import "./USDT.sol";

contract Marketplace is ReentrancyGuard,AccessControl,EIP712,BasicMetaTransaction,Initializable{

    // Variables
    address payable public feeAccount; // the account that receives fees
    uint public feePercent; // the fee percentage on sales 
    uint public itemCount; 
    INFT public nft;
    Usd public USDT;
    IUniswapV2Router02 public uniswapRouter;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    // string private constant SIGNING_DOMAIN = "LazyNFT-Voucher";
    // string private constant SIGNATURE_VERSION = "1";
    string[] URI; 
    address[] buyer;


    // itemId->  Item
    mapping(address => mapping(uint => Item)) public userListings;
    mapping(uint=>bool)voucherUsed;
    mapping (address => uint256) fundsPending;

    event Offered(
        uint itemId,
        address indexed nft,
        uint tokenId,
        uint price,
        address indexed seller
    );
    event Bought(
        uint itemId,
        address indexed nft,
        uint tokenId,
        uint price,
        address indexed seller,
        address indexed buyer
    );

    function initialize(address nftContract, uint _feePercent,address payable admin) public initializer{
        nft = INFT(nftContract);
        feeAccount = payable(_msgSender());
        feePercent = _feePercent;
        _setupRole(MINTER_ROLE, admin);
        _setupRole(DEFAULT_ADMIN_ROLE,admin);
    }

    struct Item 
    {
       uint itemId;
        IERC721 nft;
        uint tokenId;
        uint price;
        address payable seller;
        bool sold;
    }

    struct NFTvoucher
    {
        uint tokenId;
        string tokenUri;
        uint price;
        bytes signature;
    }
    
    

    function redeem(address redeemer, NFTvoucher calldata voucher) public payable returns (uint256) {
    require(voucherUsed[voucher.tokenId]!=true,"Voucher already used");
    address signer = _verify(voucher);
    require(hasRole(MINTER_ROLE, signer), "Signature invalid or unauthorized");// ?
    require(msg.value >= voucher.price, "Insufficient funds to redeem");
    nft.mint(signer, voucher.tokenId,voucher.tokenUri);
    // nft.setTokenURI(voucher.tokenId, voucher.tokenUri);
    nft.transfer(signer, redeemer, voucher.tokenId);
    fundsPending[signer] += msg.value;
    voucherUsed[voucher.tokenId] = true;
    return voucher.tokenId;
  }

  function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(hasRole(MINTER_ROLE, _msgSender()), "Only authorized minters can withdraw");
    address payable receiver = payable(_msgSender());
    uint amount = fundsPending[receiver];
    fundsPending[receiver] = 0;       // preventing re-entrancy attack.
    (bool success, bytes memory data) = receiver.call{value : amount}("");
    require(success,"Funds could not be withdrawn");
  }
  function pendingFunds() external view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
    return fundsPending[_msgSender()];
  }
    function _hash(NFTvoucher calldata voucher) internal view returns(bytes32){
        return _hashTypedDataV4((keccak256(abi.encode(keccak256("NFT voucher(uint256 itemId,uint256 price,string tokenURI)"),
        voucher.tokenId,
        voucher.price,
        keccak256(bytes(voucher.tokenUri))
        ))));
    
    }
    function _verify(NFTvoucher calldata voucher) internal view returns (address) {
    bytes32 digest = _hash(voucher);
    return ECDSA.recover(digest, voucher.signature);
    }

  function getChainID() public view override returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override (AccessControl) returns (bool) {
    return AccessControl.supportsInterface(interfaceId);
    }



    //second time listing and buying functions

    // Make item to offer on the marketplace
    function listItem(IERC721 _nft, uint _tokenId, uint _price) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        // increment itemCount
        itemCount ++;
        // transfer nft
        _nft.transferFrom(_msgSender(), address(this), _tokenId);
        // add new item to items mapping
        userListings[_msgSender()][itemCount] = Item (
            itemCount,
            _nft,
            _tokenId,
            _price,
            payable(_msgSender()),
            false
        );
        // emit Offered event
        emit Offered(
            itemCount,
            address(_nft),
            _tokenId,
            _price,
            _msgSender()
        );
    }
    function swapMaticWithUSDT() external payable
    {
        address[] memory path=new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = address(USDT);
        uint amountOutMin= uniswapRouter.getAmountsOut(msg.value,path)[1];
        uniswapRouter.swapExactETHForTokens{value:msg.value}(amountOutMin,path,msg.sender,block.timestamp);
    }
    function swapUSDTWithMatic(uint tokenAmount) external payable
    {
        address[] memory path = new address[](2);
        path[0]=address(USDT);
        path[1]=uniswapRouter.WETH();
        uint amountOutMin= uniswapRouter.getAmountsOut(tokenAmount,path)[1];
        IERC20(USDT).transferFrom(msg.sender,address(this),tokenAmount);
        IERC20(USDT).approve(address(uniswapRouter),tokenAmount);
        uniswapRouter.swapExactTokensForETH(tokenAmount,amountOutMin,path,msg.sender,block.timestamp);
    }
    function purchaseItem(uint _itemId) external payable nonReentrant {
        uint _totalPrice = getTotalPrice(_itemId);
        
        Item storage item = userListings[_msgSender()][_itemId];
        
        require(_itemId > 0 && _itemId <= itemCount, "item doesn't exist");
        
        require(msg.value >= _totalPrice, "not enough ether to cover item price and market fee");
        
        require(!item.sold, "item already sold");
        
        // pay seller and feeAccount
        item.seller.transfer(item.price);
        
        feeAccount.transfer(_totalPrice - item.price);
        
        // update item to sold
        item.sold = true;
        
        //transfer the nft to the buyer
        item.nft.transferFrom(address(this), _msgSender(), item.tokenId);
        
        // emit Bought event
        emit Bought(
            _itemId,
            address(item.nft),
            item.tokenId,
            item.price,
            item.seller,
            _msgSender()
        );
    }
      
    function getTotalPrice(uint _itemId) view public returns(uint){
        return((userListings[_msgSender()][_itemId].price*(100 + feePercent))/100);
    }

    function _msgSender() internal override(Context,BasicMetaTransaction) view returns(address sender) 
    {
        super._msgSender();
    }

}