module Publisher::BasicCoin {
    use std::signer;

    const MODULE_OWNER: address = @Publisher;

    // Error codes
    const ENOT_MODULE_OWNER: u64 = 0;
    const EINSUFFICIENT_BALANCE: u64 = 1;
    const EALREADY_HAS_BALANCE: u64 = 2;
    const EEQUAL_ADDR: u64 = 4;

    struct Coin<phantom CoinType> has store {
        value: u64,
    }

    struct Balance<phantom CoinType> has key {
        coin: Coin<CoinType>,
    }

    public fun publish_balance<CoinType>(account: &signer) {
        assert!(!exists<Balance<CoinType>>(signer::address_of(account)), EALREADY_HAS_BALANCE);
        let empty_coin = Coin<CoinType> { value: 0 };
        move_to(account, Balance<CoinType> { coin: empty_coin });
    }

    spec publish_balance {
        include PublishSchema<CoinType> {addr: signer::address_of(account), amount: 0};
    }

    spec schema PublishSchema<CoinType> {
        addr: address;
        amount: u64;

        aborts_if exists<Balance<CoinType>>(addr);

        ensures exists<Balance<CoinType>>(addr);
        let post balance_post = global<Balance<CoinType>>(addr).coin.value;
        ensures balance_post == amount;
    }

    public fun mint<CoinType>(module_owner: &signer, mint_addr: address, amount: u64) acquires Balance {
        assert!(signer::address_of(module_owner) == MODULE_OWNER, ENOT_MODULE_OWNER);

        deposit(mint_addr, Coin<CoinType> { value: amount });
    }

    spec mint {
        let addr_from = signer::address_of(module_owner);

        aborts_if addr_from != MODULE_OWNER;

        include DepositSchema<CoinType> {addr: mint_addr, amount};
    }

    public fun balance_of<CoinType>(owner: address): u64 acquires Balance {
        borrow_global<Balance<CoinType>>(owner).coin.value
    }

    spec balance_of {
        pragma aborts_if_is_strict;
        aborts_if !exists<Balance<CoinType>>(owner);
    }

    // public(script) fun transfer(from: &signer, to: address, amount: u64) acquires Balance {
    public fun transfer<CoinType>(from: &signer, to: address, amount: u64) acquires Balance {
        let from_addr = signer::address_of(from);
        assert!(from_addr != to, EEQUAL_ADDR);
        let check = withdraw<CoinType>(signer::address_of(from), amount);
        deposit<CoinType>(to, check);
    }

    spec transfer {
        let addr_from = signer::address_of(from);

        let balance_from = global<Balance<CoinType>>(addr_from).coin.value;
        let balance_to = global<Balance<CoinType>>(to).coin.value;
        let post balance_from_post = global<Balance<CoinType>>(addr_from).coin.value;
        let post balance_to_post = global<Balance<CoinType>>(to).coin.value;

        aborts_if !exists<Balance<CoinType>>(addr_from);
        aborts_if !exists<Balance<CoinType>>(to);
        aborts_if balance_from < amount;
        aborts_if balance_to + amount > MAX_U64;
        aborts_if addr_from == to;

        ensures balance_from_post == balance_from - amount;
        ensures balance_to_post == balance_to + amount;
    }

    fun deposit<CoinType>(addr: address, check: Coin<CoinType>) acquires Balance {
        let Coin { value: _amount } = check;
        let balance = balance_of<CoinType>(addr);
        let balance_ref = &mut borrow_global_mut<Balance<CoinType>>(addr).coin.value;
        *balance_ref = balance + _amount;
    }

    spec deposit {
        let balance = global<Balance<CoinType>>(addr).coin.value;
        let check_value = check.value;

        aborts_if !exists<Balance<CoinType>>(addr);
        aborts_if balance + check_value > MAX_U64;

        let post balance_post = global<Balance<CoinType>>(addr).coin.value;
        ensures balance_post == balance + check_value;
    }

    spec schema DepositSchema<CoinType> {
        addr: address;
        amount: u64;
        let balance = global<Balance<CoinType>>(addr).coin.value;

        aborts_if !exists<Balance<CoinType>>(addr);
        aborts_if balance + amount > MAX_U64;

        let post balance_post = global<Balance<CoinType>>(addr).coin.value;
        ensures balance_post == balance + amount;
    }

    fun withdraw<CoinType>(addr: address, amount: u64): Coin<CoinType> acquires Balance {
        let balance = balance_of<CoinType>(addr);
        assert!(balance >= amount, EINSUFFICIENT_BALANCE);
        let balance_ref = &mut borrow_global_mut<Balance<CoinType>>(addr).coin.value;
        *balance_ref = balance - amount;
        Coin<CoinType> { value: amount }
    }

    spec withdraw {
        let balance = global<Balance<CoinType>>(addr).coin.value;
        aborts_if !exists<Balance<CoinType>>(addr);
        aborts_if balance < amount;

        let post balance_post = global<Balance<CoinType>>(addr).coin.value;
        ensures balance_post == balance - amount;
        ensures result == Coin<CoinType> { value: amount };
    }

    struct TestCoin {}

    #[test(account = @0x1)]
    #[expected_failure]
    fun mint_non_owner<TestCoin>(account: signer) acquires Balance {
        publish_balance<TestCoin>(&account);
        assert!(signer::address_of(&account) != MODULE_OWNER, 0);
        mint<TestCoin>(&account, @0x1, 10);

        // let addr = 0x1::signer::address_of(&account);
        // mint(account, 10);
        // assert!(borrow_global<Coin>(addr).value == 11, 0);
    }

    #[test(account = @Publisher)]
    fun mint_check_balance(account: signer) acquires Balance {
        let addr = signer::address_of(&account);
        publish_balance<TestCoin>(&account);
        mint<TestCoin>(&account, @Publisher, 42);
        assert!(balance_of<TestCoin>(addr) == 42, 0);
    }

    #[test(account = @0x1)]
    fun publish_balance_has_zero(account: signer) acquires Balance {
        let addr = signer::address_of(&account);
        publish_balance<TestCoin>(&account);
        assert!(balance_of<TestCoin>(addr) == 0, 0);
    }

    #[test(account = @0x1)]
    #[expected_failure(abort_code = 2)]
    fun publish_balance_already_exists(account: signer) {
        publish_balance<TestCoin>(&account);
        publish_balance<TestCoin>(&account);
    }

    #[test(account = @0x1)]
    #[expected_failure]
    fun balance_of_dne<TestCoin>(account: signer) {
        let addr = signer::address_of(&account);
        assert!(exists<Balance<TestCoin>>(addr), 0);
    }

    #[test]
    #[expected_failure]
    fun withdraw_dne<TestCoin>() acquires Balance {
        Coin { value: _ } = withdraw<TestCoin>(@0x1, 0)
    }

    #[test(account = @0x1)]
    #[expected_failure]
    fun withdraw_too_much<TestCoin>(account: signer) acquires Balance {
        let addr = signer::address_of(&account);
        publish_balance<TestCoin>(&account);
        Coin { value: _ } = withdraw<TestCoin>(addr, 1)
    }

    #[test(account = @Publisher)]
    fun can_withdraw_amount(account: signer) acquires Balance {
        publish_balance<TestCoin>(&account);
        let amount = 1000;
        let addr = signer::address_of(&account);
        mint<TestCoin>(&account, addr, amount);
        let Coin { value } = withdraw<TestCoin>(addr, amount);
        assert!(value == amount, 0);
    }
}