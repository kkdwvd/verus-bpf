// SPDX-License-Identifier: GPL-2.0
#![no_std]
use verus_builtin_macros::verus;

verus! {
#[no_mangle]
pub fn add_one(x: u64) -> (r: u64)
    ensures r == x.wrapping_add(1),
{
    x.wrapping_add(1)
}
}
