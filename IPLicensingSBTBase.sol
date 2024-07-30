// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./TBAManager.sol";

/// @title IP授权SBT基础合约
/// @notice 这个抽象合约实现了IP授权SBT的基本功能
abstract contract IPLicensingSBTBase is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // TBA管理器合约
    TBAManager public immutable tbaManager;
    // 代币ID计数器
    uint256 private _tokenIdCounter;

    // 基础IPFS哈希
    string private _baseIPFSHash;

    // 事件：授权被接受
    event LicenseAccepted(
        address indexed minter,
        uint256 indexed tokenId,
        address indexed tba
    );
    // 事件：授权被铸造
    event LicenseMinted(
        uint256 indexed tokenId,
        address indexed tba,
        address indexed nftContract,
        uint256 nftTokenId
    );
    // 事件：基础IPFS哈希更新
    event BaseIPFSHashUpdated(string newBaseIPFSHash);

    // 错误：无效签名
    error InvalidSignature();
    // 错误：灵魂绑定代币
    error SoulboundToken();
    // 错误：TBA管理器地址为零地址
    error ZeroAddressTBAManager();

    /// @notice 构造函数
    /// @param name 代币名称
    /// @param symbol 代币符号
    /// @param _tbaManager TBA管理器地址
    /// @param baseIPFSHash 基础IPFS哈希
    constructor(
        string memory name,
        string memory symbol,
        address _tbaManager,
        string memory baseIPFSHash
    ) ERC721(name, symbol) Ownable(msg.sender) {
        if (_tbaManager == address(0)) revert ZeroAddressTBAManager();
        tbaManager = TBAManager(_tbaManager);
        _baseIPFSHash = baseIPFSHash;
    }

    /// @notice 内部函数：铸造SBT
    /// @param tba TBA地址
    /// @param nftContract NFT合约地址
    /// @param nftTokenId NFT代币ID
    function _mintSBT(
        address tba,
        address nftContract,
        uint256 nftTokenId
    ) internal returns (uint256) {
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        _safeMint(tba, newTokenId);

        emit LicenseMinted(newTokenId, tba, nftContract, nftTokenId);
        return newTokenId;
    }

    /// @notice 返回代币的URI
    /// @param tokenId 代币ID
    /// @return 代币的URI
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireOwned(tokenId);
        return
            string(
                abi.encodePacked(
                    "ipfs://",
                    _baseIPFSHash,
                    "/",
                    tokenId.toString(),
                    ".json"
                )
            );
    }

    /// @notice 设置基础IPFS哈希
    /// @param newBaseIPFSHash 新的基础IPFS哈希
    function setBaseIPFSHash(string memory newBaseIPFSHash) external onlyOwner {
        _baseIPFSHash = newBaseIPFSHash;
        emit BaseIPFSHashUpdated(newBaseIPFSHash);
    }

    /// @notice 内部函数：在转移前检查
    /// @dev 重写ERC721的_beforeTokenTransfer函数，确保token不可转移
    /// @param from 发送地址
    /// @param to 接收地址
    /// @param firstTokenId 第一个token ID
    /// @param batchSize 批量大小
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual {
        if (from != address(0) && to != address(0)) revert SoulboundToken();
    }

    /// @notice 禁止转移token
    /// @dev 重写ERC721的transferFrom函数，确保token不可转移
    /// @param from 发送地址
    /// @param to 接收地址
    /// @param tokenId token ID
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        revert SoulboundToken();
    }

    /// @notice 禁止安全转移token（带数据）
    /// @dev 重写ERC721的safeTransferFrom函数，确保token不可转移
    /// @param from 发送地址
    /// @param to 接收地址
    /// @param tokenId token ID
    /// @param data 附加数据
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        revert SoulboundToken();
    }

    /// @notice 禁止销毁token
    /// @dev 添加burn函数并禁用它，确保token不可销毁
    /// @param tokenId token ID
    function burn(uint256 tokenId) public virtual {
        revert SoulboundToken();
    }

    /// @notice 重写授权函数，禁止授权
    function approve(address to, uint256 tokenId) public pure override {
        revert SoulboundToken();
    }

    /// @notice 重写批量授权函数，禁止批量授权
    function setApprovalForAll(
        address operator,
        bool approved
    ) public pure override {
        revert SoulboundToken();
    }
}
