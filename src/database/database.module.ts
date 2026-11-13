import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DbHealthController } from './db-health.controller.js';
import { buildDataSourceOptions } from './typeorm.config.js';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        ...buildDataSourceOptions((key) => config.get<string>(key)),
        // Docker may still be starting when Nest boots.
        retryAttempts: 5,
        retryDelay: 2000,
      }),
    }),
  ],
  controllers: [DbHealthController],
})
export class DatabaseModule {}
