#include "ws.h"

/* no copy constructor, no reset */
Ws* _ws_new(W* w){
    Ws* ws = (Ws*)calloc(1, sizeof(Ws));
    ws->head = w;
    ws->tail = w;
    return ws;
}

/* checkless attachment */
void _retail(Ws* ws, W* w){
    ws->tail->next = w;
    ws->tail = w;
}

Ws* _ws_add(Ws* ws, W* w){
    if(!ws){
        ws = _ws_new(w);
    } else {
        if(ws->tail){
            _retail(ws, w);
        } else {
            fprintf(stderr, "WARNING: cannot add to tailless table\n");
        }
    }
    return ws;
}

Ws* ws_new(const W* w){
    Ws* ws = (Ws*)calloc(1, sizeof(Ws));
    W* w2 = w_isolate(w);
    ws->head = w2;
    ws->tail = w2;
    return ws;
}

Ws* ws_add(Ws* ws, const W* w){
    W* w2 = w_isolate(w);
    if(!ws){
        ws = _ws_new(w2);
    } else {
        if(ws->tail){
            _retail(ws, w2);
        } else {
            fprintf(stderr, "WARNING: cannot add to tailless table\n");
        }
    }
    return ws;
}

Ws* ws_add_val(Ws* ws, Class cls, void* v){
    W* w = w_new(cls, v);
    ws = _ws_add(ws, w);
    return ws;
}

void _join(Ws* a, Ws* b){
    a->tail->next = b->head;
    a->tail = b->tail;
}

Ws* ws_join(Ws* a, Ws* b){
    if(b && b->head){
        if(a && a->head){
            _join(a, b);
        } else {
            a = b;
        }
    }
    return a;
}

void ws_assert_class(const W* w, Class cls){
    if(!w){
        fprintf(
            stderr,
            "Class assertion failed! Got NULL, expected %s.\n",
            w_class_str(cls)
        );
    } else if(w->cls != cls){
        fprintf(
            stderr,
            "Class assertion failed! Got %s, expected %s.\n",
            w_class_str(w->cls), w_class_str(cls)
        );
    }
}

void ws_assert_type(const W* w, VType type){
    if(!w){
        fprintf(
            stderr,
            "Type assertion failed! Got NULL, expected %s.\n",
            w_type_str(type)
        );
    } else {
        VType t = get_value_type(w->cls);
        if(t != type){
            fprintf(
                stderr,
                "Type assertion failed! Got %s, expected %s.\n",
                w_type_str(t), w_type_str(type)
            );
        }
    }
}

Ws* ws_increment(const Ws* ws){
    Ws* n = NULL;
    if(ws && ws->head != ws->tail){
        n = (Ws*)malloc(sizeof(Ws));
        n->head = ws->head->next;
    }
    return n;
}

void ws_print_r(const Ws* ws, Ws*(*recurse)(const W*), int depth){

    if(!ws || !ws->head) return;

    for(W* w = ws->head; w; w = w->next){
        for(int i = 0; i < depth; i++){ printf("  "); }

        printf("%s\n", w_str(w));
        Ws* rs = recurse(w);

        if(!rs) continue;

        for(W* r = rs->head; r; r = r->next){
            ws_print_r(r->value.ws, recurse, depth+1);
        }
    }
}

void ws_print(const Ws* ws, Ws*(*recurse)(const W*)){
    ws_print_r(ws, recurse, 0);
}

int ws_length(const Ws* ws){
    if(!ws) return 0;
    int size = 0;
    for(W* w = ws->head; w; w = w->next){ size++; }
    return size;
}


Ws* ws_flatten( const Ws* ws, Ws*(*recurse)(const W*) ){
    return ws_rfilter(ws, recurse, w_keep_all);
}

Ws* ws_rfilter( const Ws* ws, Ws*(*recurse)(const W*), bool(*criterion)(const W*) ){
    Ws* result = NULL;
    if(!ws || !ws->head) return NULL;
    for(W* w = ws->head; w; w = w->next){
        if(criterion(w)){
            result = ws_add(result, w);
        }
        Ws* rs = recurse(w);
        if(!rs) continue;
        for(W* r = rs->head; r; r = r->next){
            Ws* down = ws_rfilter(r->value.ws, recurse, criterion);
            result = ws_join(result, down);
        }
    }
    return result;
}

Ws* ws_prfilter(
    const Ws* ws,
    const W* p,
    Ws*(*recurse)(const W*, const W*),
    bool(*criterion)(const W*, const W*),
    const W*(*nextval)(const W* p, const W* w)
){
    Ws* result = NULL;
    if(!ws || !ws->head) return NULL;
    for(W* w = ws->head; w; w = w->next){
        if(criterion(w, p)){
            result = ws_add(result, w);
        }
        Ws* rs = recurse(w, p); 
        if(!rs) continue;
        for(W* r = rs->head; r; r = r->next){
            Ws* down = ws_prfilter(r->value.ws, nextval(p, w), recurse, criterion, nextval);
            result = ws_join(result, down);
        }
    }
    return result;
}

void ws_prmod(
    const Ws* ws,
    const W* p,
    Ws*(*recurse)(const W*, const W*),
    void(*mod)(const W*, const W*),
    const W*(*nextval)(const W* p, const W* w)
){
    if(!ws || !ws->head) return;
    for(W* w = ws->head; w; w = w->next){
        mod(w, p);
        Ws* rs = recurse(w, p); 
        if(!rs) continue;
        for(W* r = rs->head; r; r = r->next){
            ws_prmod(r->value.ws, nextval(p, w), recurse, mod, nextval);
        }
    }
}

void ws_map_pmod(Ws* xs, const Ws* ps, void(*pmod)(Ws*, const W*)){
    if(!ps) return;
    for(W* p = ps->head; p; p = p->next){
        pmod(xs, p);
    }
}

Ws* ws_split_couplet(const W* c){
    ws_assert_type(c, V_COUPLET);
    Ws* result = NULL;
    W* paths = c->value.couplet->lhs;
    switch(paths->cls){
        case K_LIST:
            {
                for(W* p = paths->value.ws->head; p; p = p->next){
                    W* nc = w_isolate(c);
                    nc->value.couplet->lhs = p;
                    result = ws_add(result, nc); 
                }
            }
            break;
        case K_PATH:
        case K_LABEL:
        case K_NAME:
            result = ws_add(result, c); 
            break;
        default:
            fprintf(stderr, "ERROR: invalid lhs type in couplet (%s:%d)", __func__, __LINE__);
            break;
    }
    return result;
}

Ws* ws_map_split(const Ws* ws, Ws*(*split)(const W*)){
    if(!ws) return NULL;
    Ws* result = NULL;
    for(W* w = ws->head; w; w = w->next){
       result = ws_join(result, split(w)); 
    }
    return result;
}

void ws_mod(const Ws* ws, void(*mod)(const W*)){
    if(!ws) return;
    for(W* w = ws->head; w; w = w->next){
       mod(w); 
    }
}

void ws_2mod(const Ws* xs, const Ws* ys, void(*mod)(const W*, const W*)){
    if(!(xs && ys)) return;
    for(W* x = xs->head; x; x = x->next){
        for(W* y = ys->head; y; y = y->next){ 
            mod(x, y);
        }
    }
}

void ws_3mod(const Ws* xs, const Ws* ys, const Ws* zs, void(*mod)(const W* x, const W* y, const W* z)){
    if(!(xs && ys && zs)) return;
    for(W* x = xs->head; x; x = x->next){
        for(W* y = ys->head; y; y = y->next){ 
            for(W* z = zs->head; z; z = z->next){ 
                mod(x, y, z);
            }
        }
    }
}

void ws_pmod(const Ws* ws, const W* p, void(*mod)(const W*, const W*)){
    for(W* w = ws->head; w; w = w->next){
       mod(w, p); 
    }
}

void ws_filter_mod(const Ws* top,
    Ws*(*xfilter)(const Ws*),
    void(*mod)(const W* x)
){
    Ws* xs = xfilter(top);
    ws_mod(xs, mod);
}

void ws_filter_2mod(const Ws* top,
    Ws*(*xfilter)(const Ws*),
    Ws*(*yfilter)(const Ws*),
    void(*mod)(const W* x, const W* y)
){
    Ws* xs = xfilter(top);
    Ws* ys = yfilter(top);
    ws_2mod(xs, ys, mod);
}

void ws_filter_3mod(const Ws* top,
    Ws*(*xfilter)(const Ws*),
    Ws*(*yfilter)(const Ws*),
    Ws*(*zfilter)(const Ws*),
    void(*mod)(const W* x, const W* y, const W* z)
){
    Ws* xs = xfilter(top);
    Ws* ys = yfilter(top);
    Ws* zs = zfilter(top);
    ws_3mod(xs, ys, zs, mod);
}


void ws_cone(const Ws* top,
    Ws*(*xfilter)(const Ws*),
    Ws*(*yfilter)(const Ws*, const W*),
    void(*mod)(const Ws*, const W* x, const W* y)
){
    Ws* xs = xfilter(top);
    for(W* x = xs->head; x; x = x->next){
        Ws* ys = yfilter(top, x);
        for(W* y = ys->head; y; y = y->next){ 
            mod(top, x, y);
        }
    }
}

void ws_2cone(const Ws* top,
    Ws*(*xfilter)(const Ws* top),
    Ws*(*yfilter)(const Ws* top, const W* x),
    Ws*(*zfilter)(const Ws* top, const W* x, const W* y),
    void(*mod)(const Ws* top, const W* x, const W* y, const W* z)
){
    Ws* xs = xfilter(top);
    for(W* x = xs->head; x; x = x->next){
        Ws* ys = yfilter(top, x);
        for(W* y = ys->head; y; y = y->next){ 
            Ws* zs = zfilter(top, x, y);
            for(W* z = zs->head; z; z = z->next){ 
                mod(top, x, y, z);
            }
        }
    }
}

// === nextval functions ============================================

const W* w_nextval_always(const W* p, const W* w){ return p->next; }

const W* w_nextval_never(const W* p, const W* w){ return p; }

const W* w_nextval_ifpath(const W* p, const W* w) {
    W* next = NULL;
    if(w->cls == T_PATH){
        W* lhs = p->value.couplet->lhs;
        switch(lhs->cls){
            case K_PATH:
                next = w_isolate(w);
                next->value.couplet->lhs->value.ws = ws_increment(lhs->value.ws);
                break;
            case K_LIST:
                next = NULL;
                fprintf(stderr, "Not supported (%s:%d)", __func__, __LINE__);
                break;
            default:
                next = NULL;
                break;
        }
    } else {
        next = w_isolate(w);
    }
    return next;
}

// === filter criteria ==============================================
// ------------------------------------------------------------------

bool w_is_manifold(const W* w){
    return w->cls == C_MANIFOLD;
}

bool w_keep_all(const W* w){
    return true;
}

bool w_name_match(const W* w, const W* p){
    return false; // STUB
}

// === recursion rules ==============================================
// NOTE: recursion rules are splits
// ------------------------------------------------------------------

Ws* ws_recurse_most(const W* w){
    if(!w) return NULL;
    Ws* rs = NULL;
    switch(get_value_type(w->cls)){
        case V_WS:
            rs = ws_add_val(rs, P_WS, w->value.ws);
            break;
        case V_COUPLET:
            {
                W* lhs = w->value.couplet->lhs;
                if(w_is_recursive(lhs)){
                    rs = ws_add_val(rs, P_WS, lhs->value.ws);
                }
                W* rhs = w->value.couplet->rhs;
                if(w_is_recursive(rhs)){
                    rs = ws_add_val(rs, P_WS, rhs->value.ws);
                }
            }
        default:
            break;
    }
    return rs;
}

Ws* ws_recurse_ws(const W* w){
    if(!w) return NULL;
    Ws* rs = NULL;
    switch(get_value_type(w->cls)){
        case V_WS:
            rs = ws_add_val(rs, P_WS, w->value.ws);
            break;
        default:
            break;
    }
    return rs;
}

Ws* ws_recurse_none(const W* w){
    return NULL;
}

bool ws_cmp_lhs_to_label(W* lhs, Label* b){

    bool result;

    switch(lhs->cls){
        case K_NAME:
            result = false;
            break;
        case K_LABEL:
            result = label_cmp(lhs->value.label, b);
            break;
        case K_PATH:
            result = label_cmp(lhs->value.ws->head->value.label, b);
            break;
        case K_LIST:
            result = false;
            fprintf(stderr, "Recursion into K_LIST not supported (%s:%d)", __func__, __LINE__);
            break;
        default:
            result = false;
            fprintf(stderr, "Illegal left hand side (%s:%d)", __func__, __LINE__);
            break;
    }

    return result;
}

Ws* ws_recurse_path(const W* w, const W* p){

    Ws* result;

    ws_assert_type(p, V_COUPLET);

    switch(w->cls){
        case C_NEST:
            result = w->value.ws;
            break;
        case T_PATH:
            result = ws_cmp_lhs_to_label(w->value.couplet->lhs, p->value.label) ?
                w->value.ws : NULL;
            break;
        default:
            result = NULL;
            break;
    }

    return result;
}
