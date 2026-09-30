// Shim mínimo para enlazar libneedle.a sin libc++ del sistema.
//
// El engine prebuilt de Cactus (C++) necesita UN solo símbolo que el
// libc++.so del Android SDK no exporta: std::__1::__hash_memory.
// Es la función hash interna de libc++ usada solo en tablas hash en runtime:
// cualquier hash determinístico sirve porque las colisiones se resuelven
// por igualdad. Acá va FNV-1a, más que suficiente.
//
// Si instalás libc++ del sistema (yay -S libc++), este shim no hace falta:
// compilá sin NEEDLE_CXX_DIR y con -l c++ del sistema.
//
// Se compila como C++ para que el símbolo salga mangled correcto.
#include <stddef.h>
#include <stdint.h>

namespace std {
namespace __1 {
size_t __hash_memory(const void *p, size_t n) {
    const unsigned char *d = (const unsigned char *)p;
    uint64_t h = 1469598103934665603ULL; // FNV offset basis
    for (size_t i = 0; i < n; i++) {
        h ^= d[i];
        h *= 1099511628211ULL; // FNV prime
    }
    return (size_t)h;
}
}
}
