pragma circom 2.0.0;

template MatMul2x2() {
    signal input a00;
    signal input a01;
    signal input a10;
    signal input a11;
    signal input b00;
    signal input b01;
    signal input b10;
    signal input b11;

    signal output c00;
    signal output c01;
    signal output c10;
    signal output c11;

    c00 <== a00 * b00 + a01 * b10;
    c01 <== a00 * b01 + a01 * b11;
    c10 <== a10 * b00 + a11 * b10;
    c11 <== a10 * b01 + a11 * b11;
}

component main = MatMul2x2();
