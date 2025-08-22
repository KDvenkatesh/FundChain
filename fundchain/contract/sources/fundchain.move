module fundchain_addr::fundchain {
    use std::signer;

    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::table;

    struct NGOVault has store {
        id: u64,
        ngo: address,
        project_id: u64,
        match_amount: u64,      
        min_months: u8,        
        fulfilled_months: u8,   
        is_active: bool,
        funds: coin::Coin<AptosCoin>, 
    }

    struct VaultRegistry has key {
        next_id: u64,
        vaults: table::Table<u64, NGOVault>,
    }

    public fun module_address(): address { @fundchain_addr }

    public entry fun init(deployer: &signer) {
        let addr = signer::address_of(deployer);
        assert!(addr == module_address(), 1); 
        assert!(!exists<VaultRegistry>(addr), 2);
        move_to(deployer, VaultRegistry { next_id: 0, vaults: table::new<u64, NGOVault>() });
    }

    public entry fun create_vault(
    ngo: &signer,
    project_id: u64,
    match_amount: u64,
    min_months: u8
    // The 'payment: coin::Coin<AptosCoin>' parameter is removed
) acquires VaultRegistry {

    assert!(match_amount > 0, 10);
    assert!(min_months > 0, 11);

    // Create the 'payment' coin by withdrawing directly from the sender's (ngo's) account.
    let payment = coin::withdraw<AptosCoin>(ngo, match_amount);

    let reg = borrow_global_mut<VaultRegistry>(module_address());
    let id = reg.next_id;
    reg.next_id = id + 1;

    let vault = NGOVault {
        id,
        ngo: signer::address_of(ngo),
        project_id,
        match_amount,
        min_months,
        fulfilled_months: 0,
        is_active: true,
        funds: payment, // Store the newly created coin object
    };
    table::add(&mut reg.vaults, id, vault);
}

    public entry fun record_month(ngo: &signer, vault_id: u64) acquires VaultRegistry {
        let reg = borrow_global_mut<VaultRegistry>(module_address());
        let v = table::borrow_mut<u64, NGOVault>(&mut reg.vaults, vault_id);
        assert!(v.is_active, 20);
        assert!(signer::address_of(ngo) == v.ngo, 21);
        v.fulfilled_months = v.fulfilled_months + 1;
    }

    public entry fun release_match(ngo: &signer, vault_id: u64) acquires VaultRegistry {
        let addr = signer::address_of(ngo);
        let reg = borrow_global_mut<VaultRegistry>(module_address());
        let v = table::borrow_mut<u64, NGOVault>(&mut reg.vaults, vault_id);

        assert!(v.is_active, 30);
        assert!(addr == v.ngo, 31);
        assert!(v.fulfilled_months >= v.min_months, 32);
        assert!(coin::value(&v.funds) == v.match_amount, 33);

        let payout = coin::extract(&mut v.funds, v.match_amount);
        v.is_active = false;
        coin::deposit<AptosCoin>(addr, payout);
    }

    public fun get_vault_summary(vault_id: u64): (address, u64, u64, u8, u8, bool) acquires VaultRegistry {
        let reg = borrow_global<VaultRegistry>(module_address());
        let v = table::borrow<u64, NGOVault>(&reg.vaults, vault_id);
        (v.ngo, v.project_id, v.match_amount, v.min_months, v.fulfilled_months, v.is_active)
    }
}