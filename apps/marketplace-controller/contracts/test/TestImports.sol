pragma solidity 0.4.24;

import "@aragon/os/contracts/acl/ACL.sol";
import "@aragon/os/contracts/factory/DAOFactory.sol";
import "@aragon/os/contracts/kernel/Kernel.sol";
import "@aragon/minime/contracts/MiniMeToken.sol";
import "@aragon/apps-agent/contracts/Agent.sol";
import "@aragon/contract-helpers-test/contracts/0.4/token/TokenMock.sol";
import "@1hive/apps-marketplace-bancor-formula/contracts/BancorFormula.sol";
import "@1hive/apps-marketplace-shared-test-helpers/contracts/ForceSendETH.sol";


// HACK to workaround truffle artifact loading on dependencies
contract TestImports {
  constructor() public {
    // to avoid lint error
  }
}
