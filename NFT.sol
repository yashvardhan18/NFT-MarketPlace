// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "./Interfaces/INFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFT is ERC721URIStorage,Ownable
{
    uint256 private constant  maxMintLimit=100;
    uint256 tokenIndex=0; 

    mapping(string=>uint)URIIndex;

    event minted(
        uint tokenID,
        string tokenURI
    );

    constructor() ERC721("nft","sym"){ }

    function mint(address buyer,uint tokenCount,string memory _tokenURI) external
    {
        _safeMint(buyer, tokenCount);
        _setTokenURI(tokenCount,_tokenURI);
        //EVENT
        emit minted(
            tokenCount,
            _tokenURI
        );

    }
    function bulkMint(address to, string[] memory URI) external onlyOwner{
        require(URI.length<=maxMintLimit,"more than max mint limit");
        URIIndex[URI[tokenIndex]]=tokenIndex;
        for(uint i=0;i<URI.length;i++ & tokenIndex++){
        _safeMint(to,tokenIndex);
        _setTokenURI(tokenIndex,URI[tokenIndex]);
    }

    }
    function bulkTransfer(address[] memory to,string[] memory URI)external onlyOwner{
        require(to.length==URI.length,"Uneven array length");
        for(uint i=0;i<URI.length;i++){
            transferFrom(msg.sender,to[i],URIIndex[URI[i]]);
        }
    }
    function setTokenURI(uint tokenID, string memory _tokenURI) external 
    {
        _setTokenURI(tokenID,_tokenURI);
    }
}