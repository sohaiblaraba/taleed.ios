#if DEBUG
import SwiftUI

/// §3 Marketplace components.
struct GalleryMarketplace: View {
    @Environment(\.locale) private var locale
    @State private var products: [ProductSummary] = []

    var body: some View {
        let copy = GalleryCopy(locale)
        GallerySection(id: "product-cards", number: "3.1", title: "Product card",
                       note: "2-column grid, gap 8; whole card opens, heart is optimistic.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: TaleedLayout.ProductGrid.gap), GridItem(.flexible())],
                      spacing: TaleedLayout.ProductGrid.gap) {
                ForEach(products.prefix(4)) { product in
                    ProductCard(product: product, onTap: {}, onFavorite: { toggleFavorite(product.id) })
                }
            }
        }
        .onAppear { loadProducts(copy) }
        GallerySection(id: "price", number: "3.2", title: "Price treatment", note: "DA suffix, tabular digits (D-5).") {
            VStack(alignment: .leading, spacing: TaleedSpacing.s12) {
                HStack(spacing: TaleedSpacing.s16) {
                    PriceText(amount: 800, style: TaleedFont.priceCard)
                    PriceText(amount: 12500, style: TaleedFont.priceListRow)
                    PriceText(amount: 1_234_567, style: TaleedFont.priceDetail)
                }
                PriceDetailBlock(
                    amount: 4800,
                    negotiableLabel: copy("Prix négociable", "السعر قابل للتفاوض", "Negotiable price"),
                    meta: [
                        .init(icon: .mapPin, text: copy("Oran · 2,4 km", "وهران · 2.4 كم", "Oran · 2.4 km")),
                        .init(icon: .clock, text: copy("Publié il y a 2 heures", "نُشر منذ ساعتين", "Published 2 hours ago")),
                        .init(icon: .truck, text: copy("Livraison disponible", "التوصيل متاح", "Delivery available")),
                        .init(icon: .eye, text: copy("84 vues", "84 مشاهدة", "84 views")),
                    ]
                )
            }
        }
        GallerySection(id: "list-rows", number: "3.3", title: "Product list row", note: "Standard (108 media) and dense") {
            VStack(spacing: TaleedSpacing.s16) {
                ProductListContainer {
                    ForEach(products.suffix(2)) { product in
                        ProductListRow(product: product, onTap: {}, onFavorite: { toggleFavorite(product.id) })
                    }
                }
                ProductListContainer {
                    ForEach(products.prefix(2)) { product in
                        ProductListRow(product: product, style: .dense, onTap: {}, onFavorite: { toggleFavorite(product.id) })
                    }
                }
            }
        }
        .onAppear { loadProducts(copy) }
        GallerySection(id: "seller", number: "3.4", title: "Seller card") {
            SellerCard(
                name: "Lina N.",
                reputation: copy("4,9 ★ · 38 ventes", "4.9 ★ · 38 عملية بيع", "4.9 ★ · 38 sales"),
                isVerified: true,
                verifiedLabel: copy("Identité vérifiée", "هوية موثّقة", "Verified identity"),
                stats: [
                    .init(value: copy("< 1 h", "< 1 س", "< 1 h"), label: copy("Réponse", "الرد", "Reply")),
                    .init(value: copy("3 ans", "3 سنوات", "3 years"), label: copy("Membre", "عضو", "Member")),
                    .init(value: "98%", label: copy("Positif", "إيجابي", "Positive")),
                ],
                viewProfileTitle: copy("Voir le profil", "عرض الملف", "View profile")
            ) {}
        }
        GallerySection(id: "empty", number: "3.5", title: "Empty state") {
            EmptyState(
                title: copy("Aucun trésor trouvé", "لم نجد أي كنز", "No treasures found"),
                message: copy("Essayez une autre ville ou retirez un filtre pour voir plus d’articles.",
                              "جرّب مدينة أخرى أو أزل عامل تصفية لرؤية المزيد من الأغراض.",
                              "Try another city or remove a filter to see more items."),
                actionTitle: copy("Effacer les filtres", "مسح عوامل التصفية", "Clear filters")
            ) {}
        }
        GallerySection(id: "skeletons", number: "3.6", title: "Skeleton cards", note: "Pulse 1.2 s, max six, static with Reduce Motion.") {
            VStack(spacing: TaleedSpacing.s24) {
                SkeletonCardRow()
                SkeletonGrid(count: 2)
            }
        }
    }

    private func loadProducts(_ copy: GalleryCopy) {
        if products.isEmpty { products = GallerySamples.products(copy) }
    }

    /// Optimistic toggle, as features will do it.
    private func toggleFavorite(_ id: String) {
        guard let index = products.firstIndex(where: { $0.id == id }) else { return }
        products[index].isFavorite.toggle()
        let delta = products[index].isFavorite ? 1 : -1
        products[index].favoriteCount = max(0, (products[index].favoriteCount ?? 0) + delta)
    }
}
#endif
