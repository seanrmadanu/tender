import SwiftUI

/// Note artwork with live cash-wallet values, independent of the profile photo.
struct CashWalletCard: View {
    let account: Account
    let balanceVisible: Bool
    var reverse = false
    private let ink = Color(red: 0.18, green: 0.29, blue: 0.13)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                Image("CashGuillocheNote").resizable().interpolation(.high)
                if reverse {
                    VStack(spacing: 5) {
                        Image(systemName: "seal").font(.system(size: 38, weight: .light))
                        Text("tender").font(.system(.title3, design: .serif)).tracking(4)
                    }.foregroundStyle(ink)
                } else {
                    VStack(spacing: 8) {
                        Image("CashEngravedTitle").resizable().scaledToFit()
                            .frame(height: min(70, width * 0.22)).accessibilityLabel("Cash")
                        WalletRollingBalance(amount: account.available, roll: balanceVisible, centered: true)
                            .foregroundStyle(ink).opacity(balanceVisible ? 1 : 0)
                    }.padding(.horizontal, width * 0.18)
                }
            }.frame(width: width, height: geometry.size.height)
        }.clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(ink.opacity(0.3), lineWidth: 0.5) }
    }
}
