import { Addressable, BaseContract, BigNumberish } from "ethers";
import { Token, getBalanceChange } from "@nomicfoundation/hardhat-chai-matchers/internal/changeTokenBalance";
import { buildAssert } from "@nomicfoundation/hardhat-chai-matchers/utils";
import { getAddressOf } from "@nomicfoundation/hardhat-chai-matchers/internal/misc/account";
import { preventAsyncMatcherChaining } from "@nomicfoundation/hardhat-chai-matchers/internal/utils";


declare global {
    export namespace Chai {
        interface Assertion {
            approximatelyChangeTokenBalance(
                token: BaseContract,
                account: Addressable | string,
                balance: BigNumberish,
                error: BigNumberish
            ): AsyncAssertion;
        }
    }
}

const checkToken = (token: unknown, method: string) => {
    if (typeof token !== "object" || token === null || !("interface" in token)) {
      throw new Error(
        `The first argument of ${method} must be the contract instance of the token`
      );
    } else if ((token as BaseContract).interface.getFunction("balanceOf") === null) {
      throw new Error("The given contract instance is not an ERC20 token");
    }
}

const tokenDescriptionsCache = new Map<string, string>();

const getTokenDescription = async (token: Token): Promise<string> => {
    const tokenAddress = await token.getAddress();
    if (!tokenDescriptionsCache.has(tokenAddress)) {
      let tokenDescription;
      try {
        tokenDescription = await token.symbol();
      } catch (exc) {
        try {
          tokenDescription = await token.name();
        } catch (e2) {
            tokenDescription = `<token at ${tokenAddress}>`;
        }
      }

      tokenDescriptionsCache.set(tokenAddress, tokenDescription);
    }

    return tokenDescriptionsCache.get(tokenAddress)!;
  }


const APPROXIMATELY_CHANGE_TOKEN_BALANCE_MATCHER = "approximatelyChangeTokenBalance";

const supportApproximatelyChangeTokenBalance = (
    Assertion: Chai.AssertionStatic,
    chaiUtils: Chai.ChaiUtils
) => {
    Assertion.addMethod(
        APPROXIMATELY_CHANGE_TOKEN_BALANCE_MATCHER,
        // eslint-disable-next-line max-params
        function approximatelyChangeTokenBalance (
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            this: any,
            token: Token,
            account: Addressable | string,
            balanceChange: BigNumberish,
            error: BigNumberish

        ) {
            // Capture negated flag before async code executes; see buildAssert's jsdoc
            // eslint-disable-next-line no-underscore-dangle, no-invalid-this
            const negated = this.__flags.negate;

            // eslint-disable-next-line no-underscore-dangle, no-invalid-this
            let subject = this._obj;
            if (typeof subject === "function") {
                subject = subject();
            }

            preventAsyncMatcherChaining(
                // eslint-disable-next-line no-invalid-this
                this,
                APPROXIMATELY_CHANGE_TOKEN_BALANCE_MATCHER,
                chaiUtils
            );

            checkToken(token, APPROXIMATELY_CHANGE_TOKEN_BALANCE_MATCHER);

            const checkBalanceChange = ([actualChange, address, tokenDescription]: [
                bigint,
                string,
                string
            ]) => {
                const assert = buildAssert(negated, checkBalanceChange);

                assert(
                    actualChange <= BigInt(balanceChange),
                    `Expected the balance of ${tokenDescription} tokens for "${address}" to change no more than by ${balanceChange.toString()}, but it changed by ${actualChange.toString()}`,
                    `Expected the balance of ${tokenDescription} tokens for "${address}" to change more than by ${balanceChange.toString()}, but it changed by ${actualChange.toString()}`,
                );

                assert(
                    actualChange > BigInt(balanceChange) - BigInt(error),
                    `Expected the balance of ${tokenDescription} tokens for "${address}" to change no less than by ${balanceChange.toString()}, but it changed by ${actualChange.toString()}`,
                    `Expected the balance of ${tokenDescription} tokens for "${address}" to change less than by ${balanceChange.toString()}, but it changed by ${actualChange.toString()}`,
                );
            };

            const derivedPromise = Promise.all([
                getBalanceChange(subject, token as Token, account),
                getAddressOf(account),
                getTokenDescription(token),
            ]).then(checkBalanceChange);

            // eslint-disable-next-line no-invalid-this
            this.then = derivedPromise.then.bind(derivedPromise);
            // eslint-disable-next-line no-invalid-this
            this.catch = derivedPromise.catch.bind(derivedPromise);

            // eslint-disable-next-line no-invalid-this
            return this;
        }
    );
}

export const d2ChaiMatchers = (
    chai: Chai.ChaiStatic,
    chaiUtils: Chai.ChaiUtils
) => {
    supportApproximatelyChangeTokenBalance(chai.Assertion, chaiUtils);
}
