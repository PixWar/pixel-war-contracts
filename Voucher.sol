// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./PaymentSplitter.sol";

struct VoucherInfo {
  uint256 price;
  string data;
  address wallet;
  address contractAddress;
  bytes signature;
}

contract Voucher is AccessControl, EIP712, IERC2981, Ownable {
  bytes32 public constant GENERATE_VOUCHER_ROLE =
    keccak256("GENERATE_VOUCHER_ROLE");
  string private constant SIGNING_DOMAIN = "Voucher";
  string private constant SIGNATURE_VERSION = "1";

  PaymentSplitter paymentSplitter;
  address public royaltyReceiver;
  uint8 public royaltyPercentage;

  using Counters for Counters.Counter;
  Counters.Counter private _voucherCounter;

  event VoucherSold(
    address wallet,
    address targetContractAddress_,
    string data
  );

  constructor(
    address signer,
    address payable _royaltyReceiver,
    uint8 _royaltyPercentage
  ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
    _setupRole(GENERATE_VOUCHER_ROLE, signer);
    paymentSplitter = PaymentSplitter(_royaltyReceiver);
    royaltyReceiver = _royaltyReceiver;
    royaltyPercentage = _royaltyPercentage;
    _voucherCounter.increment();
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControl, IERC165)
    returns (bool)
  {
    return
      type(IERC2981).interfaceId == interfaceId ||
      super.supportsInterface(interfaceId);
  }

  function buy(VoucherInfo calldata voucher) external payable {
    require(msg.value == voucher.price, "Voucher: Invalid price amount");
    address signer = verifyVoucherInfo(voucher);
    require(
      hasRole(GENERATE_VOUCHER_ROLE, signer),
      "Voucher: Signature invalid or unauthorized"
    );
    require(_msgSender() == voucher.wallet, "Voucher: Invalid wallet");
    paymentSplitter.receiveFromPrimarySale{value: msg.value}();
    emit VoucherSold(voucher.wallet, voucher.contractAddress, voucher.data);
  }

  function verifyVoucherInfo(VoucherInfo calldata voucher)
    internal
    view
    returns (address)
  {
    bytes32 digest = hashVoucherInfo(voucher);
    return ECDSA.recover(digest, voucher.signature);
  }

  function hashVoucherInfo(VoucherInfo calldata voucherInfo)
    internal
    view
    returns (bytes32)
  {
    bytes memory info = abi.encodePacked(
      voucherInfo.contractAddress,
      voucherInfo.price,
      voucherInfo.wallet,
      voucherInfo.data
    );

    bytes memory domainInfo = abi.encodePacked(
      this.getChainID(),
      SIGNING_DOMAIN,
      SIGNATURE_VERSION,
      address(this)
    );

    return
      ECDSA.toEthSignedMessageHash(
        keccak256(abi.encodePacked(info, domainInfo))
      );
  }

  function getChainID() external view returns (uint256) {
    uint256 id;
    assembly {
      id := chainid()
    }
    return id;
  }

  function setRoyalty(address creator, uint8 _royaltyPercentage)
    public
    onlyOwner
  {
    royaltyReceiver = creator;
    royaltyPercentage = _royaltyPercentage;
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
