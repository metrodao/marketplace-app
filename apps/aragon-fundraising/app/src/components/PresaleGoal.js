import React from 'react'
import { Box, Button } from '@aragon/ui'
import CircleGraph from '../components/CircleGraph'
import { useApi, useAppState, useConnectedAccount } from '@aragon/api-react'
import { Presale } from '../constants'
import { formatBigNumber } from '../utils/bn-utils'

export default () => {
  // *****************************
  // background script state
  // *****************************
  const {
    presale: {
      state,
      contributionToken: { symbol, decimals },
      goal,
      totalRaised,
    },
  } = useAppState()

  // *****************************
  // aragon api
  // *****************************
  const api = useApi()
  const account = useConnectedAccount()

  const circleColor = {
    [Presale.state.PENDING]: '#ecedf1',
    [Presale.state.FUNDING]: '#21c1e7',
    [Presale.state.GOAL_REACHED]: '#2CC68F',
    [Presale.state.REFUNDING]: '#FF6969',
  }

  const handleOpenTrading = event => {
    event.preventDefault()
    if (account) {
      api
        .closePresale()
        .toPromise()
        .catch(console.error)
    }
  }

  return (
    <Box heading="Presale Goal">
      <div className="circle">
        <CircleGraph value={totalRaised.div(goal).toNumber()} size={224} width={6} color={circleColor[state]} />
        <div>
          <p css="color: #212B36; display: inline;">{formatBigNumber(totalRaised, decimals)}</p> {symbol} of{' '}
          <p css="color: #212B36; display: inline;">{formatBigNumber(goal, decimals)}</p> {symbol}
        </div>
        {state === Presale.state.GOAL_REACHED && (
          <>
            <p>Presale goal completed! 🎉</p>
            <Button wide mode="strong" label="Open trading" css="margin-top: 1rem; width: 100%;" onClick={handleOpenTrading}>
              Open trading
            </Button>
          </>
        )}
        {state === Presale.state.REFUNDING && (
          <>
            <p css="color: #212B36; font-weight: 300; font-size: 16px;">Unfortunately, the target goal for this project has not been reached.</p>
            <Button wide mode="strong" label="Refund Presale Tokens" css="margin-top: 1rem; width: 100%;" onClick={() => console.log('asdasd')}>
              Refund Presale Tokens
            </Button>
          </>
        )}
      </div>
    </Box>
  )
}
