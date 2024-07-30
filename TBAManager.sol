// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC6551Registry} from "./interfaces/IERC6551Registry.sol";
import {Multicall3} from "./interfaces/Multicall3.sol";

interface IAccountProxy {
    function initialize(address implementation) external;
}

interface IERC1271 {
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (bytes4 magicValue);
}

/// @title TBA管理器
/// @notice 这个合约管理Token Bound Accounts (TBAs)的创建和初始化
contract TBAManager is Ownable {
    IERC6551Registry public registry;
    address public accountProxy;
    address public accountImplementation;
    bytes32 public immutable SALT = bytes32(0);
    bytes4 private constant MAGICVALUE = 0x1626ba7e;
    Multicall3 public multicall;

    event TBACreated(
        address indexed tba,
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 chainId
    );
    event RegistryUpdated(address newRegistry);
    event AccountProxyUpdated(address newAccountProxy);
    event AccountImplementationUpdated(address newAccountImplementation);
    event MulticallUpdated(address newMulticall);

    error TBAAlreadyDeployed();
    error NotNFTOwner();
    error InvalidAddress();

    /// @notice 构造函数
    /// @param _registry ERC6551注册表地址
    /// @param _accountProxy 账户代理地址
    /// @param _accountImplementation 账户实现地址
    /// @param _multicall Multicall3合约地址
    constructor(
        address _registry,
        address _accountProxy,
        address _accountImplementation,
        address _multicall
    ) Ownable(msg.sender) {
        if (
            _registry == address(0) ||
            _accountProxy == address(0) ||
            _accountImplementation == address(0) ||
            _multicall == address(0)
        ) revert InvalidAddress();
        registry = IERC6551Registry(_registry);
        accountProxy = _accountProxy;
        accountImplementation = _accountImplementation;
        multicall = Multicall3(_multicall);
    }

    /// @notice 创建并初始化TBA
    /// @param tokenContract NFT合约地址
    /// @param tokenId NFT的tokenId
    /// @param chainId NFT的链ID
    /// @return 创建的TBA地址
    function createTBA(
        address tokenContract,
        uint256 tokenId,
        uint256 chainId
    ) external returns (address) {
        address predictedTBA = getTBAAddress(tokenContract, tokenId, chainId);

        if (predictedTBA.code.length != 0) revert TBAAlreadyDeployed();
        if (IERC721(tokenContract).ownerOf(tokenId) != msg.sender)
            revert NotNFTOwner();

        Multicall3.Call3[] memory calls = new Multicall3.Call3[](2);

        calls[0] = Multicall3.Call3({
            target: address(registry),
            allowFailure: false,
            callData: abi.encodeWithSelector(
                IERC6551Registry.createAccount.selector,
                accountProxy,
                SALT,
                chainId,
                tokenContract,
                tokenId
            )
        });

        calls[1] = Multicall3.Call3({
            target: predictedTBA,
            allowFailure: false,
            callData: abi.encodeWithSelector(
                IAccountProxy.initialize.selector,
                accountImplementation
            )
        });

        Multicall3.Result[] memory results = multicall.aggregate3(calls);

        address tba = abi.decode(results[0].returnData, (address));

        emit TBACreated(tba, tokenContract, tokenId, chainId);

        return tba;
    }

    /// @notice 获取TBA地址
    /// @param tokenContract NFT合约地址
    /// @param tokenId NFT的tokenId
    /// @param chainId NFT的链ID
    /// @return TBA地址
    function getTBAAddress(
        address tokenContract,
        uint256 tokenId,
        uint256 chainId
    ) public view returns (address) {
        return
            registry.account(
                accountProxy,
                SALT,
                chainId,
                tokenContract,
                tokenId
            );
    }

    /// @notice 检查TBA是否已部署
    /// @param tokenContract NFT合约地址
    /// @param tokenId NFT的tokenId
    /// @param chainId NFT的链ID
    /// @return 如果TBA已部署则返回true，否则返回false
    /// @dev 通过检查地址的代码长度来判断TBA是否已部署
    function isTBADeployed(
        address tokenContract,
        uint256 tokenId,
        uint256 chainId
    ) public view returns (bool) {
        address tba = getTBAAddress(tokenContract, tokenId, chainId);
        return tba.code.length > 0;
    }

    /// @notice 设置新的注册表地址
    /// @param _registry 新的注册表地址
    function setRegistry(address _registry) external onlyOwner {
        if (_registry == address(0)) revert InvalidAddress();
        registry = IERC6551Registry(_registry);
        emit RegistryUpdated(_registry);
    }

    /// @notice 设置新的账户代理地址
    /// @param _accountProxy 新的账户代理地址
    function setAccountProxy(address _accountProxy) external onlyOwner {
        if (_accountProxy == address(0)) revert InvalidAddress();
        accountProxy = _accountProxy;
        emit AccountProxyUpdated(_accountProxy);
    }

    /// @notice 设置新的账户实现地址
    /// @param _accountImplementation 新的账户实现地址
    function setAccountImplementation(
        address _accountImplementation
    ) external onlyOwner {
        if (_accountImplementation == address(0)) revert InvalidAddress();
        accountImplementation = _accountImplementation;
        emit AccountImplementationUpdated(_accountImplementation);
    }

    /// @notice 设置新的Multicall地址
    /// @param _multicall 新的Multicall地址
    function setMulticall(address _multicall) external onlyOwner {
        if (_multicall == address(0)) revert InvalidAddress();
        multicall = Multicall3(_multicall);
        emit MulticallUpdated(_multicall);
    }

    /// @notice 验证TBA签名
    /// @param tokenContract NFT合约地址
    /// @param tokenId NFT的tokenId
    /// @param signature 签名
    /// @return 签名是否有效
    function verifyTBASignature(
        address tokenContract,
        uint256 tokenId,
        uint256 chainId,
        bytes memory signature
    ) public view returns (bool) {
        // 首先检查 TBA 是否已部署
        if (!isTBADeployed(tokenContract, tokenId, chainId)) {
            return false;
        }

        address tba = getTBAAddress(tokenContract, tokenId, chainId);

        // 构造消息哈希
        bytes32 messageHash = keccak256(
            abi.encodePacked(tba, tokenContract, tokenId)
        );

        // 构造以太坊签名消息哈希
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        try
            IERC1271(tba).isValidSignature(ethSignedMessageHash, signature)
        returns (bytes4 magicValue) {
            return magicValue == MAGICVALUE;
        } catch {
            // 如果调用失败，返回 false
            return false;
        }
    }
}
