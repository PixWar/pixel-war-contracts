// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./PaymentSplitter.sol";
import "./IItem.sol";

contract HeroItem is IItem, ERC1155, Ownable, EIP712, IERC2981 {
  using Strings for uint256;

  struct ClaimItemsVoucher {
    uint256[] items;
    uint256[] amounts;
    bytes data;
    bytes signature;
  }

  string private constant SIGNING_DOMAIN = "Hero-Item";
  string private constant SIGNATURE_VERSION = "1";
  address private _heroContract;

  string private _contractURI;
  address public royaltyReceiver;
  uint8 public royaltyPercentage;

  mapping(address => bool) private _allowedMinters;

  constructor(
    address heroContract,
    address signer,
    address payable _royaltyReceiver,
    uint8 _royaltyPercentage,
    string memory contractURI_
  ) ERC1155("") EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
    _heroContract = heroContract;
    _allowedMinters[signer] = true;
    royaltyReceiver = _royaltyReceiver;
    royaltyPercentage = _royaltyPercentage;
    _contractURI = contractURI_;
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC1155, IERC165)
    returns (bool)
  {
    return
      type(IERC2981).interfaceId == interfaceId ||
      super.supportsInterface(interfaceId);
  }

  function contractURI() public view returns (string memory) {
    return _contractURI;
  }

  function setContractURI(string memory contractURI_) external {
    _contractURI = contractURI_;
  }

  function setUri(string memory uri_) public onlyOwner {
    _setURI(uri_);
  }

  function updateHeroContract(address heroContract) public onlyOwner {
    _heroContract = heroContract;
  }

  function mint(
    address account,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) public onlyOwner {
    _mint(account, id, amount, data);
  }

  function mintBatch(
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) public onlyOwner {
    _mintBatch(to, ids, amounts, data);
  }

  function claimFromHero(
    address signer,
    address to,
    uint256[] memory items,
    uint256[] memory amounts,
    bytes memory data
  ) public override onlyHeroContract {
    _safeBatchTransferFrom(signer, to, items, amounts, data);
  }

  function claim(ClaimItemsVoucher calldata voucher) public {
    address signer = _verifyClaimVoucher(voucher);
    require(
      _allowedMinters[signer] == true,
      "Signature invalid or unauthorized"
    );

    if (voucher.items.length > 0) {
      _safeBatchTransferFrom(
        signer,
        _msgSender(),
        voucher.items,
        voucher.amounts,
        voucher.data
      );
    }
  }

  function _verifyClaimVoucher(ClaimItemsVoucher calldata voucher)
    internal
    view
    returns (address)
  {
    bytes32 digest = _hashClaimVoucher(voucher);
    return ECDSA.recover(digest, voucher.signature);
  }

  modifier onlyHeroContract() {
    require(
      _msgSender() == _heroContract,
      "HeroItem: Only hero contract can mint from this route"
    );
    _;
  }

  function getChainID() external view returns (uint256) {
    uint256 id;
    assembly {
      id := chainid()
    }
    return id;
  }

  function _hashClaimVoucher(ClaimItemsVoucher calldata voucher)
    internal
    view
    returns (bytes32)
  {
    bytes memory changeInfo = abi.encodePacked(
      voucher.items,
      voucher.amounts,
      voucher.data
    );

    bytes memory domainInfo = abi.encodePacked(
      this.getChainID(),
      SIGNING_DOMAIN,
      SIGNATURE_VERSION,
      address(this)
    );

    return
      ECDSA.toEthSignedMessageHash(
        keccak256(abi.encodePacked(changeInfo, domainInfo))
      );
  }

  function uri(uint256 _tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    return string(abi.encodePacked(super.uri(_tokenId), _tokenId.toString()));
  }

  /// @notice Called with the sale price to determine how much royalty
  //          is owed and to whom.
  /// @param tokenId - the NFT asset queried for royalty information (not used)
  /// @param _salePrice - sale price of the NFT asset specified by _tokenId
  /// @return receiver - address of who should be sent the royalty payment
  /// @return royaltyAmount - the royalty payment amount for _value sale price
  function royaltyInfo(uint256 tokenId, uint256 _salePrice)
    external
    view
    override(IERC2981)
    returns (address receiver, uint256 royaltyAmount)
  {
    uint256 _royalties = (_salePrice * royaltyPercentage) / 100;
    return (royaltyReceiver, _royalties);
  }
}
