pragma solidity ^0.5.0;

contract InterestRateInterface {

    uint256 public constant SCALEFACTOR = 1e18;

    /// @notice get compounding level for currenct day
    function getCurrentCompoundingLevel() public view returns (uint256);

    /// @notice get compounding level for _date `_date`
    /// @param _date The date 
    function getCompoundingLevelDate(uint256 _date) public view returns (uint256);

}

contract InterestRateNone is InterestRateInterface {
    
    /// @notice get compounding level for currenct day
    function getCurrentCompoundingLevel() public view returns (uint256) {
        return SCALEFACTOR;
    }

    /// @notice get compounding level for day `_date`
    /// param _date The daynumber 
    function getCompoundingLevelDate(uint256 /* _date */) public view returns (uint256) {
        return SCALEFACTOR;
    }

}