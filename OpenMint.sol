// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IPLicensingSBTBase.sol";

/// @title 开放铸造SBT合约
/// @notice 这个合约实现了基于全局IPFS哈希的开放SBT铸造功能
contract OpenMint is IPLicensingSBTBase {
    // 控制是否允许开放铸造的状态变量
    bool public isOpenMintingEnabled;

    // 当开放铸造状态改变时触发的事件
    event OpenMintingStatusChanged(bool isEnabled);

    // 自定义错误：开放铸造未启用
    error OpenMintingNotEnabled();
    // 自定义错误：调用者不是NFT所有者
    error NotNFTOwner();
    // 自定义错误：提供的链ID无效
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
    ) IPLicensingSBTBase(name, symbol, _tbaManager, baseIPFSHash) {
        isOpenMintingEnabled = false; // 默认关闭开放铸造
    }

    /// @notice 切换开放铸造状态
    /// @dev 只有合约所有者可以调用此函数
    function toggleOpenMinting() external onlyOwner {
        isOpenMintingEnabled = !isOpenMintingEnabled;
        emit OpenMintingStatusChanged(isOpenMintingEnabled);
    }

    /// @notice 开放铸造 SBT
    /// @param nftContract NFT 合约地址
    /// @param nftTokenId NFT 的 tokenId
    /// @param chainId 链 ID
    /// @param signature TBA 签名
    /// @dev 此函数允许用户在开放铸造启用时铸造SBT
    function openMint(
        address nftContract,
        uint256 nftTokenId,
        uint256 chainId,
        bytes memory signature
    ) external nonReentrant {
        // 检查开放铸造是否启用
        if (!isOpenMintingEnabled) {
            revert OpenMintingNotEnabled();
        }
        // 验证调用者是否为NFT所有者
        if (IERC721(nftContract).ownerOf(nftTokenId) != msg.sender) {
            revert NotNFTOwner();
        }
        // 验证链ID是否匹配当前链
        if (chainId != block.chainid) {
            revert InvalidChainId();
        }

        // 检查并标记NFT是否已被铸造
        _checkAndMarkMinted(nftContract, nftTokenId);

        // 获取或创建TBA（代币绑定账户）地址
        address tba = tbaManager.getTBAAddress(
            nftContract,
            nftTokenId,
            chainId
        );
        if (!tbaManager.isTBADeployed(nftContract, nftTokenId, chainId)) {
            tba = tbaManager.createTBA(nftContract, nftTokenId, chainId);
        }

        // 验证TBA签名
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

        // 铸造SBT
        _mintSBT(tba, nftContract, nftTokenId);
    }
}
