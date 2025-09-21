import { PolkadotPriceService } from './polkadotPriceService.js';
import { SUPPORTED_CHAINS } from '../config/index.js';

export class PriceCacheService {
  private static cachedPrices: Map<string, { price: number; timestamp: number }> = new Map();
  private static refreshInterval: NodeJS.Timeout | null = null;
  private static readonly REFRESH_INTERVAL_MS = 60000; // 1 minute

  static async initialize(): Promise<void> {
    console.log('💰 Initializing Polkadot Price Cache Service...');
    await this.fetchAndCacheAllPrices();
    this.startPeriodicRefresh();
  }

  private static startPeriodicRefresh(): void {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
    
    this.refreshInterval = setInterval(async () => {
      await this.fetchAndCacheAllPrices();
    }, this.REFRESH_INTERVAL_MS);
  }

  static getCachedPrice(symbol: string): number {
    const cached = this.cachedPrices.get(symbol);
    if (cached) {
      const ageMs = Date.now() - cached.timestamp;
      if (ageMs < this.REFRESH_INTERVAL_MS) {
        return cached.price;
      }
    }
    return 0;
  }

  private static async fetchAndCacheAllPrices(): Promise<void> {
    try {
      const uniqueCoingeckoIds = [...new Set(SUPPORTED_CHAINS.map(chain => chain.coingeckoId))];
      
      for (const coinId of uniqueCoingeckoIds) {
        try {
          const response = await fetch(`https://api.coingecko.com/api/v3/simple/price?ids=${coinId}&vs_currencies=usd`);
          const data = await response.json();
          
          if (data[coinId]?.usd) {
            const price = data[coinId].usd;
            this.cachedPrices.set(coinId, { price, timestamp: Date.now() });
            console.log(`💰 Cached price for ${coinId}: $${price}`);
          }
        } catch (error) {
          console.error(`❌ Failed to fetch price for ${coinId}:`, error);
        }
      }
    } catch (error) {
      console.error('❌ Error fetching prices:', error);
    }
  }

  static async getTokenPrices(tokens: any[]): Promise<any[]> {
    return await PolkadotPriceService.getTokenPrices(tokens);
  }

  static stop(): void {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
    console.log('🛑 Price Cache Service stopped');
  }
}