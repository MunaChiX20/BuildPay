# Clarity Language
Clarity is a new language that brings smart contracts to Bitcoin. It is a decidable language, meaning you can know, with certainty, from the code itself what the program will do. Clarity is interpreted (not compiled) & the source code is published on the blockchain. Clarity gives developers a safe way to build complex smart contracts.

## Using Clarity
This repl already contains the complete setup so you do not need to install anything. You can access the REPL using `clarity-repl` & clarinet using `clarinet`.

## Example: [hello-world](https://docs.hiro.so/tutorials/clarity-hello-world)

#### To generate a clarinet project called *hello-world*:
```
clarinet new hello-world
```
#### To generate a new clarity contract:
```
# first change directory to the project location
cd hello-world/
clarinet contract new hello-world
```
Let's add some clarity code to our **hello-world.clar** smart contract.
```
(define-public (say-hi)
  (ok "hello world"))

(define-read-only (echo-number (val int))
  (ok val))
```
### Run & Test Your Smart Contract
In the **hello-world** folder, we have already setup a clarinet project using the commands above.

#### To verify if syntax of the written smart contract is correct:
```
# first change directory to the project location
cd hello-world/
clarinet check
``` 
#### To launch a local console:
```
# first change directory to the project location
cd hello-world/
clarinet console
```
### Testing within `clarinet console`
```
# this should return (ok "Hello world")
>> (contract-call? .hello-world say-hi)
# this should return (ok 42)
>> (contract-call? .hello-world echo-number 42)
```

## Documentation & Resources
* Clarity Documentation: [docs.stacks.co/write-smart-contracts](https://docs.stacks.co/write-smart-contracts/overview)
* Clarity Reference: [github.com/clarity-lang/reference](https://github.com/clarity-lang/reference)
* More Resources: [clarity-lang.org/#started](https://clarity-lang.org/#started)
