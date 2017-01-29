#!/bin/awk -f 

BEGIN {
    FS="\t"
    printf("m4_define(<[OUTDIR]>, %s)m4_dnl\n", dir) >> rules
}

$1 == "EMIT" { m[$2]["lang"]         = $3 ; next }
$1 == "CACH" { m[$2]["cache"]        = $3 ; next }
$1 == "CHEK" { m[$2]["check"][$3]    = 1  ; next }
$1 == "FUNC" { m[$2]["func"]         = $3 ; next }
$1 == "FAIL" { m[$2]["fail"]         = $3 ; next }
$1 == "HOOK" { m[$2]["hook"][$3][$4] = 1  ; next }
$1 == "INPM" { m[$2]["m"][$3]        = $4 ; next }
$1 == "INPP" { m[$2]["p"][$3]        = $4 ; next }
$1 == "INPA" { m[$2]["a"][$3]        = $4 ; next }
$1 == "INPF" { m[$2]["f"][$3]        = $4 ; next }
$1 == "NARG" { m[$2]["narg"]         = $3 ; next }

$1 == "FARG" {
    if($5 != "") { arg = $4 " __BIND__ " $5 } else { arg = $4 }
    m[$2]["arg"][$3] = arg
    next
}

END{

    for(i in m){

        arg_inp=0

        if(m[i]["narg"]){
            printf "m4_define(<[NARG_%s]>, %s)m4_dnl\n", i, m[i]["narg"] >> rules
        } else {
            printf "m4_define(<[NARG_%s]>, 0)m4_dnl\n", i >> rules
        }

        if(m[i]["lang"] == lang){
            printf "m4_define(<[MANIFOLD_%s]>, NATIVE_MANIFOLD(%s))m4_dnl\n", i, i >> rules
        } else if(m[i]["lang"] == "*"){
            printf "m4_define(<[MANIFOLD_%s]>, UNIVERSAL_MANIFOLD(%s))m4_dnl\n", i, i >> rules
        } else {
            printf "m4_define(<[MANIFOLD_%s]>, FOREIGN_MANIFOLD(%s,%s))m4_dnl\n", i, m[i]["lang"], i >> rules
        }

        if(m[i]["cache"]){
            cache = m[i]["cache"]
            printf "m4_define(<[BASECACHE_%s]>, %s)m4_dnl\n", i, cache >> rules
            printf "m4_define(<[CACHE_%s]>, DO_CACHE(%s))m4_dnl\n", i, i >> rules
            printf "m4_define(<[CACHE_PUT_%s]>, DO_PUT(%s))m4_dnl\n", i, i >> rules
        } else {
            printf "m4_define(<[CACHE_%s]>, NO_CACHE(%s))m4_dnl\n", i, i >> rules
            printf "m4_define(<[CACHE_PUT_%s]>, NO_PUT(%s))m4_dnl\n", i, i >> rules
        }

        if(length(m[i]["check"]) > 0){
            printf "m4_define(<[VALIDATE_%s]>, DO_VALIDATE(%s))m4_dnl\n", i, i >> rules
            check=""
            for(k in m[i]["check"]){
                check = sprintf("%s __AND__ <[CHECK(%s, %s)]>", check, k, i)
            }
            gsub(/^ __AND__ /, "", check) # remove initial sep
            printf "m4_define(<[CHECK_%s]>, %s)m4_dnl\n", i, check >> rules
        } else {
            printf "m4_define(<[VALIDATE_%s]>, NO_VALIDATE(%s))m4_dnl\n", i, i >> rules
        }

        if( "m" in m[i] || "p" in m[i] || "a" in m[i] || "f" in m[i]){
            arg_inp++
            k=0
            input=""
            while(1) {
                if(m[i]["m"][k]){
                    input = sprintf("%s __SEP__ <[CALL(%s, %s)]>", input, m[i]["m"][k], i)
                }
                else if(m[i]["p"][k]){
                    input = sprintf("%s __SEP__ <[%s]>", input, m[i]["p"][k])
                }
                else if(m[i]["f"][k]){
                    wrappings[m[i]["f"][k]] = 1
                    input = sprintf("%s __SEP__ <[UID_WRAP(%s)]>", input, m[i]["f"][k])
                }
                else if(m[i]["a"][k]){
                    input = sprintf("%s __SEP__ <[NTH_ARG(%s)]>", input, m[i]["a"][k])
                }
                else {
                    break
                }
                k = k + 1
            }
            gsub(/^ __SEP__ /, "", input) # remove the last sep
            printf "m4_define(<[INPUT_%s]>, %s)m4_dnl\n", i, input >> rules
        } else {
            printf "m4_define(<[INPUT_%s]>, <[]>)m4_dnl\n", i >> rules
        }

        if(length(m[i]["arg"]) > 0){
            arg_inp++
            arg=""
            for(k=0; k<length(m[i]["arg"]); k++){
                arg = sprintf("%s __SEP__ %s", arg, m[i]["arg"][k])
            }
            gsub(/^ __SEP__ /, "", arg) # remove the initial sep
            printf "m4_define(<[ARG_%s]>, <[%s]>)m4_dnl\n", i, arg >> rules
        } else {
            printf "m4_define(<[ARG_%s]>, <[]>)m4_dnl\n", i >> rules
        }

        if("hook" in m[i] && length(m[i]["hook"]) > 0){
            for(k = 0; k < 10; k++){
                if(k in m[i]["hook"]){
                    hook=""
                    for(kk in m[i]["hook"][k]){
                        hook = sprintf("%s HOOK(%s, %s) ", hook, kk, i)
                    }
                    printf "m4_define(<[HOOK%s_%s]>, <[%s]>)m4_dnl\n", k, i, hook >> rules
                } else {
                    printf "m4_define(<[HOOK%s_%s]>, <[]>)m4_dnl\n", k, i >> rules
                }
            }
        } else {
            for(k = 0; k < 10; k++){
                printf "m4_define(<[HOOK%s_%s]>, <[]>)m4_dnl\n", k, i >> rules
            }
        }

        if(m[i]["func"]){
            printf "m4_define(<[FUNC_%s]>, <[%s]>)m4_dnl\n", i, m[i]["func"] >> rules
        } else {
            printf "m4_define(<[FUNC_%s]>, NOTHING)m4_dnl\n", i >> rules
        }

        if(m[i]["fail"]){
            printf "m4_define(<[FAIL_%s]>, <[%s]>)m4_dnl\n", i, m[i]["fail"] >> rules
        } else {
            printf "m4_define(<[FAIL_%s]>, SIMPLE_FAIL)m4_dnl\n", i >> rules
        }

        # This is a hacky way to get a delimiter between the input and
        # arguments passed to the main function. arg_inp == 2 when both an
        # input and argument is given.
        if(arg_inp == 2){
            printf("m4_define(<[ARG_INP_%s]>, <[__SEP__]>)m4_dnl\n", i) >> rules
        } else {
            printf("m4_define(<[ARG_INP_%s]>, <[]>)m4_dnl\n", i) >> rules
        }
    }

    printf "PROLOGUE<[]>m4_dnl\n" >> body
    printf "m4_include(%s)m4_dnl\n", src >> body

    for(i in m){
        if(i in wrappings){
            printf sprintf("MAKE_UID(%s)m4_dnl\n", i) >> body
        }
        printf "MANIFOLD_%s<[]>m4_dnl\n", i >> body
    }

    printf "EPILOGUE<[]>m4_dnl\n" >> body

}
