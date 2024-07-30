// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IPLicensingSBTBase.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title 基于Merkle证明的SBT铸造合约（使用位图）
/// @notice 这个合约实现了使用Merkle证明来验证和铸造SBT的功能，并使用位图限制每个NFT只能铸造一次
contract MintWithMerkleProof is IPLicensingSBTBase {
    // Merkle树的根，用于验证铸造资格
    bytes32 public offersMerkleRoot;

    // 使用位图记录已铸造的NFT
    mapping(address => mapping(uint256 => uint256)) private _mintedBitmap;

    // 当Merkle根更新时触发的事件
    event OffersMerkleRootUpdated(bytes32 newRoot);

    // 自定义错误：无效的Merkle证明
    error InvalidMerkleProof();
    // 自定义错误：NFT已被铸造
    error NFTAlreadyMinted(address nftContract, uint256 nftTokenId);

    constructor(
        string memory name,
        string memory symbol,
        address _tbaManager,
        string memory baseIPFSHash,
        bytes32 initialMerkleRoot
    ) IPLicensingSBTBase(name, symbol, _tbaManager, baseIPFSHash) {
        offersMerkleRoot = initialMerkleRoot;
    }

    function setOffersMerkleRoot(bytes32 _root) external onlyOwner {
        if (_root == bytes32(0)) revert("Root cannot be zero");
        offersMerkleRoot = _root;
        emit OffersMerkleRootUpdated(_root);
    }

    function verifyMerkleOffer(
        bytes32[] memory proof,
        address nftContract,
        uint256 nftTokenId,
        uint256 chainId
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encode(nftContract, nftTokenId, chainId));
        return MerkleProof.verify(proof, offersMerkleRoot, leaf);
    }

    /// @notice 检查并标记NFT为已铸造（使用位图）
    /// @param nftContract NFT合约地址
    /// @param nftTokenId NFT代币ID
    function _checkAndMarkMinted(
        address nftContract,
        uint256 nftTokenId
    ) internal {
        uint256 wordIndex = nftTokenId / 256;
        uint256 bitIndex = nftTokenId % 256;
        uint256 word = _mintedBitmap[nftContract][wordIndex];

        if (word & (1 << bitIndex) != 0) {
            revert NFTAlreadyMinted(nftContract, nftTokenId);
        }

        _mintedBitmap[nftContract][wordIndex] = word | (1 << bitIndex);
    }

    function mintWithMerkleProof(
        bytes32[] calldata proof,
        address nftContract,
        uint256 nftTokenId,
        uint256 chainId,
        bytes memory signature
    ) external nonReentrant {
        if (!verifyMerkleOffer(proof, nftContract, nftTokenId, chainId)) {
            revert InvalidMerkleProof();
        }

        _checkAndMarkMinted(nftContract, nftTokenId);

        address tba = tbaManager.getTBAAddress(
            nftContract,
            nftTokenId,
            chainId
        );
        if (!tbaManager.isTBADeployed(nftContract, nftTokenId, chainId)) {
            tba = tbaManager.createTBA(nftContract, nftTokenId, chainId);
        }

        if (
            !tbaManager.verifyTBASignature(
                nftContract,
                nftTokenId,
                chainId,
                signature
            )
        ) {
            revert InvalidSignature();
        }

        _mintSBT(tba, nftContract, nftTokenId);
    }

    /// @notice 检查NFT是否已被铸造（使用位图）
    /// @param nftContract NFT合约地址
    /// @param nftTokenId NFT代币ID
    /// @return 是否已被铸造
    function isNFTMinted(
        address nftContract,
        uint256 nftTokenId
    ) public view returns (bool) {
        uint256 wordIndex = nftTokenId / 256;
        uint256 bitIndex = nftTokenId % 256;
        uint256 word = _mintedBitmap[nftContract][wordIndex];
        return (word & (1 << bitIndex)) != 0;
    }
}
