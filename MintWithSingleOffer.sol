// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IPLicensingSBTBase.sol";

/// @title 基于单个offer的SBT铸造合约
/// @notice 这个合约实现了基于单个offer的SBT铸造功能和授权信息管理
contract MintWithSingleOffer is IPLicensingSBTBase {
    /// @notice 授权信息结构体
    struct LicenseInfo {
        address issuer; // 授权方地址（6551帐户地址）
        address licensee; // 被授权方地址（SBT合约地址）
        uint256 startTime; // 授权开始时间
        uint256 expirationTime; // 授权结束时间
        bool forCommercialUse; // 是否用于商业用途（默认True）
        string territory; // 授权国界
        bool derivativesAllowed; // 是否支持衍生（默认False）
        string licensingUseDescription; // 授权用途描述
        uint256 licensingFixedFee; // 授权固定费用（默认0）
        uint256 revenueShare; // 商业收入分成百分比（默认0）
        bool nonTransferable; // 授权是否可转让（默认False）
    }

    /// @notice 授权offer结构体
    struct LicensingOffer {
        address nftContract; // NFT合约地址
        uint96 nftTokenId; // NFT的tokenId
        uint32 chainId; // 链ID
        uint96 expirationTime; // offer过期时间
        uint96 creationTime; // offer创建时间
        bool isValid; // offer是否有效
        bool isMinted; // offer是否已被铸造
    }

    /// @notice 存储所有授权offer
    mapping(bytes32 => LicensingOffer) public offers;
    /// @notice 存储所有已铸造SBT的授权信息
    mapping(uint256 => LicenseInfo) public tokenLicenseInfo;

    /// @notice 创建offer时触发的事件
    event OfferCreated(
        bytes32 indexed offerId,
        address nftContract,
        uint256 nftTokenId,
        uint256 chainId,
        uint256 expirationTime,
        uint256 creationTime
    );
    /// @notice 撤销offer时触发的事件
    event OfferRevoked(bytes32 indexed offerId);
    /// @notice 设置授权信息时触发的事件
    event LicenseInfoSet(uint256 indexed tokenId, LicenseInfo licenseInfo);

    /// @notice 自定义错误：无效的offer
    error InvalidOffer();
    /// @notice 自定义错误：offer已被铸造
    error OfferAlreadyMinted();
    /// @notice 自定义错误：offer已过期
    error OfferExpired();
    /// @notice 自定义错误：NFT信息不匹配
    error NFTMismatch();
    /// @notice 自定义错误：无效的链ID
    error InvalidChainId();

    /// @notice 构造函数
    /// @param name SBT的名称
    /// @param symbol SBT的符号
    /// @param _tbaManager TBA管理器地址
    /// @param baseIPFSHash 基础IPFS哈希
    constructor(
        string memory name,
        string memory symbol,
        address _tbaManager,
        string memory baseIPFSHash
    ) IPLicensingSBTBase(name, symbol, _tbaManager, baseIPFSHash) {}

    /// @notice 创建一个新的授权offer
    /// @param nftContract NFT合约地址
    /// @param nftTokenId NFT的tokenId
    /// @param chainId 链ID
    /// @param expirationTime offer过期时间
    function createOffer(
        address nftContract,
        uint256 nftTokenId,
        uint256 chainId,
        uint256 expirationTime
    ) external onlyOwner {
        if (expirationTime <= block.timestamp)
            revert("Expiration time must be in the future");

        uint256 creationTime = block.timestamp;
        bytes32 offerId = keccak256(
            abi.encode(
                nftContract,
                nftTokenId,
                chainId,
                expirationTime,
                creationTime
            )
        );

        offers[offerId] = LicensingOffer(
            nftContract,
            uint96(nftTokenId),
            uint32(chainId),
            uint96(expirationTime),
            uint96(creationTime),
            true,
            false
        );

        emit OfferCreated(
            offerId,
            nftContract,
            nftTokenId,
            chainId,
            expirationTime,
            creationTime
        );
    }

    /// @notice 撤销一个未使用的offer
    /// @param offerId 要撤销的offer的ID
    function revokeOffer(bytes32 offerId) external onlyOwner {
        LicensingOffer storage offer = offers[offerId];
        if (!offer.isValid) revert InvalidOffer();
        if (offer.isMinted) revert OfferAlreadyMinted();

        offer.isValid = false;
        emit OfferRevoked(offerId);
    }

    /// @notice 基于单个offer铸造SBT
    /// @param offerId offer的ID
    /// @param nftContract NFT合约地址
    /// @param nftTokenId NFT的tokenId
    /// @param chainId 链ID
    /// @param signature TBA签名
    /// @param licenseInfo 授权信息
    function mintWithSingleOffer(
        bytes32 offerId,
        address nftContract,
        uint256 nftTokenId,
        uint256 chainId,
        bytes memory signature,
        LicenseInfo memory licenseInfo
    ) external nonReentrant {
        LicensingOffer storage offer = offers[offerId];

        if (!offer.isValid) revert InvalidOffer();
        if (offer.isMinted) revert OfferAlreadyMinted();
        if (block.timestamp > offer.expirationTime) revert OfferExpired();
        if (
            offer.nftContract != nftContract ||
            offer.nftTokenId != nftTokenId ||
            offer.chainId != chainId
        ) revert NFTMismatch();
        if (chainId != block.chainid) revert InvalidChainId();

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

        offer.isMinted = true;
        uint256 newTokenId = _mintSBT(tba, nftContract, nftTokenId);

        // 设置授权信息
        licenseInfo.issuer = tba;
        licenseInfo.licensee = address(this);
        licenseInfo.startTime = block.timestamp;
        tokenLicenseInfo[newTokenId] = licenseInfo;

        emit LicenseInfoSet(newTokenId, licenseInfo);
    }

    /// @notice 获取指定tokenId的授权信息
    /// @param tokenId SBT的tokenId
    /// @return 授权信息
    function getLicenseInfo(
        uint256 tokenId
    ) external view returns (LicenseInfo memory) {
        return tokenLicenseInfo[tokenId];
    }
}
