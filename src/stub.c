// Not sure why, but the resultant .so files need this symbol even
// though I don't actually use it (to my knowledge...)
void* __emutls_get_address(void* _) {
    return 0;
}
