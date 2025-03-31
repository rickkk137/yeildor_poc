// SPDX-License-Identifier: UNLICENSED  
pragma solidity ^0.8.13;  
  
import "forge-std/Test.sol";  
import {IUniswapV3Pool} from "../src/interfaces/IUniswapV3Pool.sol";  
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";  
import {IMainnetRouter} from "../src/interfaces/IMainnetRouter.sol";  
  
import 'forge-std/console2.sol';  
  
contract BaseTest is Test {  
    IUniswapV3Pool pool = IUniswapV3Pool(0xe612cb2b5644Aef0Ad3e922BaE70A8374C63515F);  
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;  
  
    uint32 public twap;  
  
    int24 public tickSpacing;  
  
    uint24 public positionWidth;  
  
    int24 tickLower;  
    int24 tickUpper;  
  
    int24 public maxObservationDeviation;  
  
    function setUp() public virtual {  
        vm.createSelectFork("OPTIMSIM_RPC");//replace this one with ethereum rpc url  
        tickSpacing = IUniswapV3Pool(pool).tickSpacing();  
        deal(pool.token0(), address(this), type(uint).max);  
        deal(pool.token1(), address(this), type(uint).max);  
  
        (uint32 index0time, ,,) = pool.observations(0);  
  
        twap = 300; 
        positionWidth = uint24(4 * tickSpacing);  
        (, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();  
        _setMainTicks(tick);  
        maxObservationDeviation = 100;  
  
  
    }  
  
    function testIncreaseObs() public {  
            pool.mint(address(this), tickLower, tickUpper, 10000000e18, "test");  
            IERC20(pool.token0()).approve(address(swapRouter), type(uint).max);  
            IERC20(pool.token1()).approve(address(swapRouter), type(uint).max);  
  
            IMainnetRouter.ExactInputParams memory swapParams;  
            swapParams.amountIn = 0.55e18;  
            swapParams.deadline = block.timestamp + 1 hours;  
            swapParams.path = abi.encodePacked(pool.token0(), uint24(100), pool.token1());  

            (uint32 nextTimestamp, int56 nextCumulativeTick,,) = IUniswapV3Pool(pool).observations(0);  
            console2.log("nextTimestamp:", nextTimestamp);
            console2.log("nextCumulativeTick:", nextCumulativeTick);
            pool.increaseObservationCardinalityNext(5);   
            
            vm.warp(block.timestamp + 100);  
  
            IMainnetRouter(swapRouter).exactInput(swapParams); //increase current index  
  
             (, int24 tick, uint16 currentIndex, uint16 observationCardinality,uint16 observationCardinalityNext,,) = IUniswapV3Pool(pool).slot0();  
            assertEq(observationCardinality, 5);  
            assertEq(observationCardinalityNext, 5);

            bool status = checkPoolActivity();//checkPoolActivity should return true here but that returns false  
            assertEq(status, false);  
    }  
  
    function _setMainTicks(int24 tick) internal {  
        int24 halfWidth = int24(positionWidth / 2);  
        int24 modulo = tick % tickSpacing;  
        if (modulo < 0) modulo += tickSpacing; // if tick is negative, modulo is also negative  
        bool isLowerSided = modulo < (tickSpacing / 2);  
  
        int24 tickBorder = tick - modulo;  
        if (!isLowerSided) tickBorder += tickSpacing;  
        tickLower = tickBorder - halfWidth;  
        tickUpper = tickBorder + halfWidth;  
  
    }  
  
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes memory) external {  
  
        if (amount0 > 0) IERC20(pool.token0()).transfer(address(pool), amount0);  
        if (amount1 > 0) IERC20(pool.token1()).transfer(address(pool), amount1);  
    }  
  
    function checkPoolActivity() public view returns (bool) {  
        (, int24 tick, uint16 currentIndex, uint16 observationCardinality,,,) = IUniswapV3Pool(pool).slot0();  
  
        uint32 lookAgo = uint32(block.timestamp) - twap;  
  
        (uint32 nextTimestamp, int56 nextCumulativeTick,,) = IUniswapV3Pool(pool).observations(currentIndex);  
        int24 nextTick = tick;  
          
  
        for (uint16 i = 1; i <= observationCardinality; i++) {  
              
            uint256 index = (observationCardinality + currentIndex - i) % observationCardinality;  
  
              
            (uint32 timestamp, int56 tickCumulative,,) = IUniswapV3Pool(pool).observations(index);  
            if (timestamp == 0) {  
                revert("timestamp 0");  
            }  
            console2.log("index:", index);  
            console2.log("timestamp:", timestamp);  
            console2.log("==================================================");  
  
            tick = int24((nextCumulativeTick - tickCumulative) / int56(uint56(nextTimestamp - timestamp)));  
  
            (nextTimestamp, nextCumulativeTick) = (timestamp, tickCumulative);  
            console2.log("nextTick:", nextTick);
            console2.log("tick:", tick);
            int24 delta = nextTick - tick; 
            console2.log("delta:", delta) ;
  
            if (delta > maxObservationDeviation || delta < -maxObservationDeviation) {  
                return false;  
            }  
  
            if (timestamp < lookAgo) {  
                return true;  
            }  
            nextTick = tick;  
        }  
  
        return false;  
    }  
  
  
}  
